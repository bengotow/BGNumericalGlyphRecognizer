//
//  GlyphDetectingPaintView.m
//  SketchMath
//
//  Created by Ben Gotow on 4/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "BGNumberCanvas.h"
#import "DetectedNumber.h"
#import "CJSONSerializer.h"
#import "WTMGlyphDetector.h"

#define SHOW_LETTERS YES

@interface BGNumberCanvas (Private)

- (void)setup;

#pragma mark Touch Handling
- (void)touchesMovedExtendStroke:(CGPoint)p withTimestamp:(NSTimeInterval)time;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEndedProcess:(NSMutableArray*)newStrokePoints;

#pragma mark Managing Glyphs
- (void)destroyLastGlyph;
- (void)processNewGlyph:(WTMDetectionResult *)result;
- (void)numberDetected:(DetectedNumber*)n inPaintRect:(CGRect)r;

#pragma mark Convenience Methods
- (CGRect)rectFromPoints:(NSArray*)points;
- (void)flipStroke:(NSMutableArray*)stroke;
- (void)writeStrokeToDisk:(NSMutableArray*)stroke;
- (NSMutableArray*)mirroredStroke:(NSMutableArray*)input;
- (BOOL)collectContainedLetters:(CGRect)bounds;
- (void)submitContainedLetters:(NSArray*)letters;

#pragma mark Mathematics Support Methods
- (BOOL)detectStraightLine:(NSArray*)line angleOut:(float*)angle;
- (float)distanceToPoint:(CGPoint)p fromLineSegmentBetween:(CGPoint)l1 and:(CGPoint)l2;

@end

@implementation BGNumberCanvas

@synthesize glyphDetector, glyphDelegate, glyphDetectorLock;

- (void)setup
{
    [super setup];
    
    detectedNumbers = [[NSMutableArray alloc] init];
    prevStrokePoints = [[NSMutableArray alloc] init];
    currentStrokePoints = [[NSMutableArray alloc] init];
    prevDetectedNumber = nil;
    
    // initialize the glyph detector
    self.glyphDetector = [WTMGlyphDetector detector];
    self.glyphDetectorLock = [[NSLock alloc] init];
    
    // Add initial glyph templates from JSON files
    // Rinse and repeat for each of the gestures you want to detect
    NSArray * items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSBundle mainBundle] bundlePath] error:nil];
    for (NSString * item in items){
        if ([[item pathExtension] isEqualToString:@"json"]) {
            NSString * symbol = [item stringByDeletingPathExtension];
            NSData *jsonData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:symbol ofType:@"json"]];
            [glyphDetector addGlyphFromJSON:jsonData name:symbol];
        }
    }

    glyphDetector.delegate = self;
}

#pragma mark Touch Handling

- (void)touchesMovedExtendStroke:(CGPoint)p withTimestamp:(NSTimeInterval)time
{
    [super touchesMovedExtendStroke: p withTimestamp: time];
    
    // pass it off to the detector
    [currentStrokePoints addObject: [NSValue valueWithCGPoint: CGPointMake(p.x, self.frame.size.height - p.y)]];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    // End the touch and add the last point to the screen
    [super touchesEnded: touches withEvent:event];
    
    // If the stroke is < 4 points, it's pretty useless. Definitely not a number
    if ([currentStrokePoints count] < 3) {
        [currentStrokePoints removeAllObjects];
        return;
    }
    
    NSMutableArray * arr = [NSMutableArray arrayWithArray: currentStrokePoints];
    [self performSelectorInBackground:@selector(touchesEndedProcess:) withObject: arr];
    [currentStrokePoints removeAllObjects];
}

- (void)touchesEndedProcess:(NSMutableArray*)newStrokePoints
{
    NSLog(@"Waiting to start detection. Previous is %@", [prevDetectedNumber description]);
    [glyphDetectorLock lock];
    NSLog(@"Starting detection %@ %@", [prevDetectedNumber description], [prevDetectedNumber glyphName]);
    
    NSString * detected = nil;
    int count = [newStrokePoints count];

    // okay. how close did this line come to the previous line? If it's within a few pixels
    // of touching at any point, we want to intelligently merge this stroke with the 
    // previous one.
    BOOL likelySameCharacter = NO;
    BOOL previousCharacterWasPartial = ([[prevDetectedNumber value] isEqualToString:@"p"]);
    int closePrevPoint = 0;
    int closeCurrentPoint = 0;
    float d = 10000;
    
    if (previousCharacterWasPartial || ([[prevDetectedNumber value] isEqualToString:@"-"]) || ([[prevDetectedNumber value] isEqualToString:@"1"])) {

        for (int x = 0; x < [prevStrokePoints count]; x ++) {
            CGPoint xp = [[prevStrokePoints objectAtIndex: x] CGPointValue];
            CGPoint yp = [[newStrokePoints objectAtIndex: 0] CGPointValue];
            
            for (int y = 1; y < count; y ++) {
                CGPoint yp2 = [[newStrokePoints objectAtIndex: y] CGPointValue];
                d = [self distanceToPoint: xp fromLineSegmentBetween: yp and: yp2];
                yp = yp2;
                
                if (d <= 24) {
                    likelySameCharacter = YES;
                    closePrevPoint = x;
                    closeCurrentPoint = y;
                    break;
                }
            }
            if (likelySameCharacter)
                break;
        }
        
        // If the time since the last stroke is too great, this has to be a new stroke.
        if ([[NSDate date] timeIntervalSinceDate: prevStrokeDate] > 3.3)
            likelySameCharacter = NO;
    }
    
    // Let's find out if it's a 1 or —, because we can't
    // do detection on such a simple glyph.
    CGPoint s = [[newStrokePoints objectAtIndex: 0] CGPointValue];
    CGPoint e = [[newStrokePoints lastObject] CGPointValue];
    
    // Determine the bounds of the stroke so we can look at the midpoint
    CGRect detectedGlyphRect = [self rectFromPoints: newStrokePoints];
    CGPoint detectedGlyphCenter = CGPointMake(CGRectGetMidX(detectedGlyphRect), CGRectGetMidY(detectedGlyphRect));

    // First, let's identify the angle of the stroke
    float r = atan2f(e.y - s.y, e.x - s.x);
    
    // Only look for 1 and - if this is NOT a continuation of a previous stroke.
    // This is important because if we flag this as a 1, it won't turn a 2 into a 4
    // or complete a 5 properly.
    NSArray * middle = [newStrokePoints subarrayWithRange: NSMakeRange(count / 5 + 1, count - (count / 5 + 1))];
    BOOL small = [middle count] <= 4;
    BOOL straight = [self detectStraightLine:middle angleOut:NULL];
    
    // Awesome—if it's a line that isn't squiggly in the middle, let's break
    // it into either a 1 or – based on the angle.
    if (straight || small) {
        
        double v = M_PI  / 5;
        if ((fabs(r - M_PI / 2) < v) || (fabs(r + M_PI / 2) < v))
            detected = @"1";
        else if ((fabs(r) < v) || (fabs(r + M_PI) < v) || (fabs(r - M_PI) < v))
            detected = @"-";
    }
    
    // Is it a zero? We want the start and end to be near each other, and the shape
    // should move around a midpoint in an arc. 
    if (detected == nil) {
        // First, let's check that some point near the start and some point near the
        // end are near each other. We'll use the 1/3 of points near each end.
        float min_se_d = 10000;
        int range = MAX(count / 3, 1);
        
        for (int x = 0; x < range; x++) {
            for (int y = count - range; y < count; y++) {
                CGPoint px = [[newStrokePoints objectAtIndex: x] CGPointValue];
                CGPoint py = [[newStrokePoints objectAtIndex: y] CGPointValue];
                float se_d = sqrtf(powf(px.x - py.x, 2) + powf(px.y - py.y, 2));
                min_se_d = fminf(min_se_d, se_d);
            }
        }
        
        float max_allowed_se_d = fmaxf(detectedGlyphRect.size.width, detectedGlyphRect.size.height) / 2;
        float max_allowed_vertical_d = detectedGlyphRect.size.height / 3.5;
        
        // does the shape begin or end with a long straight vertical section? This would
        // indicate that it is a sloppy 9, not a 0. Note that we only do this test if 
        // the start and end points are not in the same horizontal plane. 
        // (i.e. if you make a weird zero with a flat side, but you connect the start
        //  and end nicely , it IS a zero. A 9 or 6 must have starts and ends in different
        //  horizontal planes.)
        
        BOOL hasStraightTail = NO;
        
        if (fabs(s.y - e.y) > detectedGlyphRect.size.height / 5) {
            NSArray * beginning = [newStrokePoints subarrayWithRange: NSMakeRange(0, count / 3)];
            NSArray * ending = [newStrokePoints subarrayWithRange: NSMakeRange(count - count / 3, count / 3)];
            float beginningAngle, endingAngle;
            
            BOOL beginningStraight = [self detectStraightLine:beginning angleOut:&beginningAngle];
            BOOL endingStraight = [self detectStraightLine:ending angleOut:&endingAngle];
            
            // Awesome—if it's a line that isn't squiggly in the middle, let's break
            // it into either a 1 or – based on the angle.
            double v = M_PI  / 7;
            
            if (beginningStraight && ((fabs(beginningAngle - M_PI / 2) < v) || (fabs(beginningAngle + M_PI / 2) < v)))
                // it's not a zero!
                hasStraightTail = YES;
                
            if (endingStraight && ((fabs(endingAngle - M_PI / 2) < v) || (fabs(endingAngle + M_PI / 2) < v)))
                // it's not a zero!
                hasStraightTail = YES;
        }
        
        BOOL niceLoop = (min_se_d < max_allowed_se_d / 3);
        BOOL badLoopButSmallVerticalGap = ((min_se_d < max_allowed_se_d) && (fabs(s.y - e.y) < max_allowed_vertical_d));

        if ((niceLoop || badLoopButSmallVerticalGap) && !hasStraightTail && (count > 0)) {
            
            // Compute the mean radius of the stroke points from the center of the
            // stroke. This is important because some tiny dot could be recognized 
            // as a zero.
            float * distances = malloc(sizeof(float) * count);
            float mean = 0;
            for (int ii = 0; ii < count; ii++) {
                CGPoint p = [[newStrokePoints objectAtIndex: ii] CGPointValue];
                distances[ii] = sqrtf(powf(p.x - detectedGlyphCenter.x, 2) + powf(p.y - detectedGlyphCenter.y, 2));
                mean += distances[ii];
            }
            mean /= count;
            
            // Next, let's iterate over the points and make sure the points 
            // make an arc in a consistent direction. For the first 1/5 of the stroke,
            // we determine the overall direction the shape moves in around the midpoint.
            
            // Now how much variance is there? If this is actually an eight and
            // not a zero, we'll get an inflection in the curvature and there
            // will be a fraction of the stroke that is moving in the "wrong" direction.
            // For the remaining 4/5 of the stroke we just look for this variance.
            
            CGPoint p = [[newStrokePoints objectAtIndex: 0] CGPointValue];
            float last = atan2f(p.y - detectedGlyphCenter.y, p.x - detectedGlyphCenter.x);
            int signComputePhaseLength = count / 5;
            float sign = 0;
            int wrong = 0;
            
            for (int ii = 1; ii < count; ii++) {
                p = [[newStrokePoints objectAtIndex: ii] CGPointValue];
                float current = atan2f(p.y - detectedGlyphCenter.y, p.x - detectedGlyphCenter.x);
                float diff = current - last;
                if (diff > M_PI)
                    diff -= 2*M_PI;
                if (diff < -M_PI)
                    diff += 2*M_PI;
                
                if (ii <= signComputePhaseLength) {
                    sign += diff;
                    if (ii == signComputePhaseLength)
                        sign /= signComputePhaseLength;
                    
                } else {
                    if (((diff > 0) && (sign < 0)) || ((diff < 0) && (sign > 0)))
                        wrong ++;
                }
                
                last = current;
            }

            
            // If our shape has a sufficiently large radius and doesn't have sections
            // going in the wrong direction, we're good: it's a zero.
            NSLog(@"%f, %d < %d / 8?", mean, wrong, count);
            if ((mean > 15) && (wrong <= fmaxf(1, count / 8)))
                detected = @"0";
        }
    }
        
    if ([detected isEqualToString:@"0"]) {
        // Has the user inscribed one or more existing glyphs in this zero? 
        // Let's see if any other letters midpoints lie within the circle.
        if ([self collectContainedLetters: detectedGlyphRect]) {
            [glyphDetectorLock unlock];
            return;
        }
        
        // You can't draw a circle to continue a previous letter, bitch.
        likelySameCharacter = NO;
    }
    
    if ([detected isEqualToString:@"0"]) {
        // See if there's another zero on top of this one—somebody could be making a 
        // ghetto-ass 8. 
        CGRect searchRect = detectedGlyphRect;
        searchRect.origin.y -= searchRect.size.height * 0.3;
        searchRect.size.height *= 1.6;
        
        //searchRect.origin.y = 1024 - (searchRect.origin.y+ searchRect.size.height);
        //searchRect = [self delocalizeRect: searchRect];
        
        for (int ii = 0; ii < [detectedNumbers count]; ii++) {
            DetectedNumber * n = [detectedNumbers objectAtIndex: ii];
            if ((CGRectIntersectsRect(searchRect, [n rect])) && ([[n value] isEqualToString:@"0"])) {
                detectedGlyphRect = CGRectUnion(detectedGlyphRect, [n rect]);
                detected = @"8";

                [[n view] removeFromSuperview];
                [detectedNumbers removeObjectAtIndex: ii];
                break;
            }
        }
    }
    
    if (([prevDetectedNumber isMatchForNumber: @"7"]) && ([detected isEqualToString: @"-"])) {
        CGPoint prevCenter = [prevDetectedNumber center];
        CGPoint detectedCenter = CGPointMake(CGRectGetMidX(detectedGlyphRect), CGRectGetMidY(detectedGlyphRect));
        
        float xDiff = fabs((prevCenter.x + [prevDetectedNumber rect].size.width * 0.3) - detectedCenter.x);
        float yDiff = fabs(prevCenter.y - detectedCenter.y);
        
        if ((yDiff < [prevDetectedNumber rect].size.height / 2) && (xDiff < [prevDetectedNumber rect].size.width / 3.2)) {        
            NSLog(@"Detected  a dash7");
            [glyphDetectorLock unlock];

            // do nothing. We've got a 7 with a dash through the middle, not a -7 or a 7-.
            return;
        }
    }

    if (!likelySameCharacter) {
        NSLog(@"New Character %@", detected);
        
        // Write the glyph points to disk, just so we can see them.
        if (SHOW_LETTERS) [self writeStrokeToDisk: [self mirroredStroke: newStrokePoints]];
        
        // If this is a new character and we haven't found a 0, 1, or - yet, let's
        // run the detector! If we did find one of those, just create the DetectedNumber synchronously.
        if (detected == nil) {
            NSMutableArray * mirroredStrokePoints = [self mirroredStroke: newStrokePoints];
            [glyphDetector setPoints: mirroredStrokePoints];
            [self processNewGlyph: [glyphDetector detectGlyph]];
            
        } else {
            DetectedNumber * n = [[DetectedNumber alloc] initWithValue: detected];
            [self numberDetected: n inPaintRect: detectedGlyphRect];
        }

    } else {
        NSLog(@"Likely part of %@ character? Detected as %@ so far.", [prevDetectedNumber glyphName], detected);
        
        // the last character was a partial and this one is either 1 or -...
        if ([[[prevDetectedNumber glyphName] substringToIndex: 2] isEqualToString:@"p4"] && ([detected isEqualToString:@"1"])) {
            [self destroyLastGlyph];
            
            [newStrokePoints addObjectsFromArray: prevStrokePoints];
            DetectedNumber * n = [[DetectedNumber alloc] initWithValue: @"4"];
            [self numberDetected: n inPaintRect: detectedGlyphRect];
        
        } else if ([[[prevDetectedNumber glyphName] substringToIndex: 2] isEqualToString:@"p5"] && ([detected isEqualToString:@"-"])) {
            [self destroyLastGlyph];
            
            [newStrokePoints addObjectsFromArray: prevStrokePoints];
            DetectedNumber * n = [[DetectedNumber alloc] initWithValue: @"5"];
            [self numberDetected: n inPaintRect: detectedGlyphRect];
        
        } else {
            
            // If we're appending this new stroke to a previous stroke, make sure we 
            // add the points properly so that the two strokes connect to make a nearly-
            // continuous stroke. Otherwise, the places where the line jumps across
            // the character will screw up recognition.
            
            // What are the constraints here? We have closeCurrentPoint and closePreviousPoint,
            // which correspond to the indexes into each stroke that are closest together.
            // We want to make these joinable. Let's make it so the previous stroke always 
            // connects to the end of the current stroke. 
            
            // To do that, we need to put closeCurrentPoint at the END of the current stroke,
            // and closePreviousPoint at the BEGINNING of the previous stroke. 
            if (closeCurrentPoint < count / 2) {
                [self flipStroke: newStrokePoints];
            }
            if (closePrevPoint > [prevStrokePoints count] / 2)
                [self flipStroke: prevStrokePoints];
            
            // Do the detection before we attach the previous stroke
            [glyphDetector setPoints: [self mirroredStroke: newStrokePoints]];
            WTMDetectionResult * withoutPrevious = [glyphDetector detectGlyph];
            
            // Merge the point data
            [newStrokePoints addObjectsFromArray: prevStrokePoints];
            NSLog(@"Writing combined");
            // Write the glyph points to disk, just so we can see them.
            [self writeStrokeToDisk: [self mirroredStroke: newStrokePoints]];

            // Do the detection with the previous stroke
            [glyphDetector setPoints: [self mirroredStroke: newStrokePoints]];
            WTMDetectionResult * withPrevious = [glyphDetector detectGlyph];
            
            
            
            // Let's see which has the highest score, and process that one as the new glyph.
            // We do this so that if you attach a 4 to a 2 or some shit like that, it 
            // doesn't try to pass it off as a crappy looking 8 or something.
            if ((detected) && (fmaxf(withPrevious.bestScore, withoutPrevious.bestScore) < 2)) {
                DetectedNumber * n = [[DetectedNumber alloc] initWithValue: detected];
                [self numberDetected: n inPaintRect: detectedGlyphRect];
                
            } else {
            
                WTMDetectionResult * best;
                if ((withPrevious.bestScore > 3) || (withPrevious.bestScore > withoutPrevious.bestScore))
                    best = withPrevious;
                else {
                    best = withoutPrevious;
                    
                    BOOL withoutPreviousIsP = [[[withoutPrevious.bestMatch name] substringToIndex:1] isEqualToString:@"p"];
                    if (withoutPreviousIsP) {
                        NSString * pLetter = [[withoutPrevious.bestMatch name] substringWithRange: NSMakeRange(1, 1)];
                        NSString * withPreviousLetter = [[withPrevious.bestMatch name] substringToIndex: 1];
                        
                        if ([pLetter isEqualToString: withPreviousLetter])
                            best = withPrevious;
                    }
                }
                
                // We're extending the previous character, so let's delete whatever the detector
                // gave us when we ran it through the first time, and then detect it again.
                if (best.bestScore == withPrevious.bestScore)
                    [self destroyLastGlyph];
                [self processNewGlyph: best];
            }
        }   
    }
    
    // Clean things up for the user to draw something new
    prevStrokePoints = [NSMutableArray arrayWithArray: newStrokePoints];
    prevStrokeDate = [NSDate date];
    
    NSLog(@"Finished detection");
    [glyphDetectorLock unlock];
}

#pragma mark Managing Glyphs

- (void)destroyLastGlyph
{
    NSLog(@"Destroying last glyph!");
    [[prevDetectedNumber view] removeFromSuperview];
    [detectedNumbers removeObject: prevDetectedNumber];
    prevDetectedNumber = nil;
}

- (void)processNewGlyph:(WTMDetectionResult *)result
{
    if (result.success == NO)
        return;
        
    if (result.bestScore > 1.4) {
        DetectedNumber * n = [[DetectedNumber alloc] init];
        [n setValue: [[result.bestMatch name] substringToIndex:1]];
        [n setGlyphName: [result.bestMatch name]];
        [self numberDetected: n inPaintRect: [self rectFromPoints: [glyphDetector points]]];
        
        // identify the secondary choice for the last detected letter 
        NSArray * sortedResults = [result.allScores sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* obj1, NSDictionary* obj2) {
            float diff = [[obj1 objectForKey:@"score"] doubleValue] - [[obj2 objectForKey:@"score"] doubleValue];
            if (diff > 0)
                return NSOrderedAscending;
            else if (diff < 0)
                return NSOrderedDescending;
            else
                return NSOrderedSame;
        }];
        
        for (NSDictionary * result in sortedResults) {
            NSString * num = [[result objectForKey:@"name"] substringToIndex:1];
            if (([num isEqualToString: [n value]] == YES) || ([[result objectForKey:@"score"] doubleValue] < 1.5))
                continue;
            [n setValueSecondary: num];
            NSLog(@"Set secondary: %@", num);
            break;
        }
    }
}

- (void)numberDetected:(DetectedNumber*)n inPaintRect:(CGRect)r
{
    [n setRect: r];
    [n setCenter: CGPointMake(CGRectGetMidX(r), r.origin.y + r.size.height / 4)];
    
    prevDetectedNumber = n;
    [detectedNumbers addObject: n];

    if (SHOW_LETTERS) {
        r.origin.y = 1024 - (r.origin.y+ r.size.height);
        
        if (r.size.width < 100)
            r.size.width = 100;
        if (r.size.height < 50)
            r.size.height = 50;
         
        UIView * v = [[UIView alloc] initWithFrame: r];
        [v setUserInteractionEnabled: NO];
        [n setView: v];
        
        UILabel * l = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, r.size.width, r.size.height)];
        [l setTextColor: [UIColor redColor]];
        [l setText:[n value]];
        [l setTextAlignment: NSTextAlignmentCenter];
        [l setContentMode: UIViewContentModeCenter];
        [l setBackgroundColor: [UIColor clearColor]];
        [l setFont:[UIFont boldSystemFontOfSize: 50]];
        [v addSubview: l];

        if ([n valueSecondary]) {
            l = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, r.size.width, r.size.height)];
            [l setTextColor: [UIColor blueColor]];
            [l setText:[n valueSecondary]];
            [l setTextAlignment: NSTextAlignmentCenter];
            [l setContentMode: UIViewContentModeCenter];
            [l setBackgroundColor: [UIColor clearColor]];
            [l setFont:[UIFont boldSystemFontOfSize: 50]];
            [n setView: l];
            [v addSubview: l];
        }
        [self.superview addSubview: v];
    }
    
    if ([glyphDelegate respondsToSelector:@selector(detectedNumber:)])
        [glyphDelegate detectedNumber: n];
}

#pragma mark Convenience Methods

- (CGRect)rectFromPoints:(NSArray*)points
{
    CGRect r = CGRectZero;
    for (NSValue * v in points){ 
        if (r.size.width == 0) {
            r = CGRectMake([v CGPointValue].x ,[v CGPointValue].y, 1,1);
        } else  {
            r = CGRectUnion(r, CGRectMake([v CGPointValue].x, [v CGPointValue].y, 1, 1));
        }
    }

    return r;
}

- (void)flipStroke:(NSMutableArray*)stroke
{
    for (int ii = 0; ii < [stroke count]; ii++) {
        [stroke insertObject:[stroke lastObject] atIndex:ii];
        [stroke removeLastObject];
    }
}

- (void)writeStrokeToDisk:(NSMutableArray*)stroke
{
    CJSONSerializer * n = [CJSONSerializer serializer];
    NSMutableArray * ar = [NSMutableArray array];
    
    for (NSValue * p in stroke)
        [ar addObject: [NSArray arrayWithObjects:[NSNumber numberWithInt: [p CGPointValue].x],[NSNumber numberWithInt: [p CGPointValue].y], nil]];
    
    NSData * data = [n serializeArray:[NSArray arrayWithObject: ar] error:nil];
    NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding]);
}

- (NSMutableArray*)mirroredStroke:(NSMutableArray*)input
{
    NSMutableArray * stroke = [NSMutableArray arrayWithArray: input];
    
    // Okay. Before we do recognition, we want to mirror the shape over the Y axis.
    // To do this, we first determine the upper and lower bounds of the stroke.
    float maxy = 0;
    float miny = 11100;
    int maxyii = 0;
    
    int count = [stroke count];
    
    for (int ii = 0; ii < count; ii++) {
        NSValue * v = [stroke objectAtIndex: ii];
        miny = fminf([v CGPointValue].y, miny);
        if ([v CGPointValue].y > maxy) {
            maxy = [v CGPointValue].y;
            maxyii = ii;
        }
    }

    // Reverse the direction of the stroke so that the end of the stroke is at the
    // bottom. This way, when we flip, there isn't a vertical line from the top
    // (end of first stroke) to the bottom (end of mirrored stroke)
    if (maxyii < count / 2) 
    [self flipStroke: stroke];


    // Now add all of the upside down points by reflecting the stroke over the Y axis
    // work from the point nearest the bottom of the drawing back to zero
    for (int ii = count - 1; ii >= 0; ii--) {
        NSValue * v = [stroke objectAtIndex: ii];
        CGPoint p2 = CGPointMake([v CGPointValue].x, 2 * maxy - miny - ([v CGPointValue].y - miny));
        [stroke addObject:[NSValue valueWithCGPoint: p2]];
    }
    
    return stroke;
}

- (BOOL)collectContainedLetters:(CGRect)bounds
{
    NSMutableArray * containedLetters = [NSMutableArray array];
    NSLog(@"Submitting Answer with characters:");
    
    for (int ii = [detectedNumbers count]-1; ii >= 0; ii--) {
        CGRect other = [[detectedNumbers objectAtIndex: ii] rect];
        if (CGRectContainsPoint(bounds, CGPointMake(CGRectGetMidX(other), CGRectGetMidY(other)))) {
            DetectedNumber * x = [detectedNumbers objectAtIndex: ii];
            [containedLetters addObject: x];
        }
    }
    
    // If the zero contains other letters, let's sort them so that they
    // read left to right, and them pass them to our delegate
    if ([containedLetters count] > 0) {
        [self performSelectorOnMainThread:@selector(submitContainedLetters:) withObject:containedLetters waitUntilDone:NO];
        return YES;
    }
    return NO;
}

- (void)submitContainedLetters:(NSArray*)letters
{
    NSMutableArray * sortedLetters = [[letters sortedArrayUsingComparator:^NSComparisonResult(DetectedNumber* obj1, DetectedNumber* obj2) {
        float diff = CGRectGetMidX([obj1 rect]) - CGRectGetMidX([obj2 rect]);
        if (diff < 0)
            return NSOrderedAscending;
        else if (diff > 0)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }] mutableCopy];

    // if there's a -, it must be the first character. Otherwise it is very likely
    // the line above the result (i.e. the bottom bar of an addition / mult. problem!)
    for (int ii = [sortedLetters count] - 1; ii >= 1; ii--) {
        if ([[(DetectedNumber*)[sortedLetters objectAtIndex: ii] value] isEqualToString: @"-"])
            [sortedLetters removeObjectAtIndex: ii];
    }
    
    CGRect r = [[sortedLetters objectAtIndex: 0] rect];
    for (int ii = 1; ii < [sortedLetters count]; ii++) {
        DetectedNumber * d = [sortedLetters objectAtIndex: ii];
        r = CGRectUnion(r, [d rect]);
        
        NSLog(@"(%@ or %@)", [d value], [d valueSecondary]);
    }
    
    // Compute the screen coordinates of the inscribing circle and send that along too.
    CGRect boundsWorld = r;
     boundsWorld.origin.y = 1024 - (boundsWorld.origin.y+ boundsWorld.size.height);
     [glyphDelegate answerProvided: sortedLetters atPoint: CGPointMake(CGRectGetMidX(boundsWorld), CGRectGetMidY(boundsWorld))];
}

#pragma mark Mathematics Support Methods

- (BOOL)detectStraightLine:(NSArray*)line angleOut:(float*)angle
{
    CGPoint s = [[line objectAtIndex: 0] CGPointValue];
    CGPoint e = [[line lastObject] CGPointValue];
    
    // First, let's identify the angle of the stroke
    float r = atan2f(e.y - s.y, e.x - s.x);
    if (angle != NULL)
        *angle = r;

    // iterate over all the points along the length of the stroke and 
    // see if there is any variance in the angles between points.
    float rVariance = 0;
    for (int ii = 1; ii < [line count]; ii++) {
        CGPoint p = [[line objectAtIndex: ii-1] CGPointValue];
        CGPoint q = [[line objectAtIndex: ii] CGPointValue];
        float pr = r - atan2f(p.y - q.y, p.x - q.x);
        if (pr >= M_PI / 2)
            pr -= M_PI;
        if (pr <= -M_PI / 2)
            pr += M_PI;
        rVariance += fabs(pr);
    }
    rVariance /= [line count];
    
    NSLog(@"Detecting straight line: %f < 0.21?", rVariance);
    if (fabs(rVariance) < 0.21)
        return YES;
    return NO;
}

- (float)distanceToPoint:(CGPoint)p fromLineSegmentBetween:(CGPoint)l1 and:(CGPoint)l2
{
    float A = p.x - l1.x;
    float B = p.y - l1.y;
    float C = l2.x - l1.x;
    float D = l2.y - l1.y;

    float dot = A * C + B * D;
    float len_sq = C * C + D * D;
    float param = dot / len_sq;

    float xx, yy;

    if (param < 0 || (l1.x == l2.x && l1.y == l2.y)) {
        xx = l1.x;
        yy = l1.y;
    }
    else if (param > 1) {
        xx = l2.x;
        yy = l2.y;
    }
    else {
        xx = l1.x + param * C;
        yy = l1.y + param * D;
    }

    float dx = p.x - xx;
    float dy = p.y - yy;

    return sqrtf(dx * dx + dy * dy);
}

- (void)clear
{    
    [super clear];
    
    for (DetectedNumber * n in detectedNumbers)
        [[n view] removeFromSuperview];
    [detectedNumbers removeAllObjects];
    prevDetectedNumber = nil;
}

@end
