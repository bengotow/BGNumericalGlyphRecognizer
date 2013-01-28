//
//  GlyphDetectingPaintView.h
//  SketchMath
//
//  Created by Ben Gotow on 4/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "BGCanvas.h"
#import "WTMGlyphDetector.h"
#import "DetectedNumber.h"

@protocol BGNumberCanvasDelegate <NSObject>

- (void)detectedNumber:(DetectedNumber*)number;
- (void)answerProvided:(NSArray*)detectedNumbers atPoint:(CGPoint)p;

@end

@interface BGNumberCanvas : BGCanvas <WTMGlyphDelegate>
{
    NSMutableArray  * detectedNumbers;
    DetectedNumber  * prevDetectedNumber;
    
    NSMutableArray  * prevStrokePoints;
    NSDate *          prevStrokeDate;
    
    NSMutableArray  * currentStrokePoints;
}

@property (nonatomic, assign) NSObject<BGNumberCanvasDelegate> * glyphDelegate;
@property (nonatomic, retain) WTMGlyphDetector *  glyphDetector;
@property (nonatomic, retain) NSLock * glyphDetectorLock;

- (void)clear;


@end
