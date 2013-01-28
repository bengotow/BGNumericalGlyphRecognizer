//
//  SimplePaintView.m
//  ScribbleMath
//
//  Created by Ben Gotow on 6/6/12.
//  Copyright (c) 2012 Foundry376. All rights reserved.
//

#import "BGCanvas.h"

@implementation BGCanvas

@synthesize strokeColor;
@synthesize strokeSize;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)awakeFromNib
{
    [self setup];
}

- (void)dealloc
{
    CGLayerRelease(paintLayer);
    paintLayer = nil;
}

- (void)setup
{
    self.strokeColor = [UIColor blackColor];
    self.strokeSize = 5;
}

- (void)clear
{
    CGContextRef c = CGLayerGetContext(paintLayer);
    CGContextClearRect(c, self.bounds);
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    
    if (!paintLayer) {
        paintLayer = CGLayerCreateWithContext(c, [self bounds].size, NULL);
        CGContextSetInterpolationQuality(CGLayerGetContext(paintLayer), kCGInterpolationHigh);
        CGContextSetAllowsAntialiasing(CGLayerGetContext(paintLayer), YES);
    }
    
    CGContextSaveGState(c);
    CGContextClipToRect(c, rect);
    CGContextDrawLayerAtPoint(c, CGPointZero, paintLayer);
    CGContextRestoreGState(c);
}

- (void)addStrokeFromPoint:(CGPoint)a toPoint:(CGPoint)b
{
    CGContextRef pc = CGLayerGetContext(paintLayer);
    CGContextSetFillColorWithColor(pc, [strokeColor CGColor]);
    
    // make a line out of circles
    float d = sqrtf(powf(a.x - b.x, 2) + powf(a.y - b.y, 2));
    int steps = floorf(d / (self.strokeSize / 4.0)) + 1;
    float dstepx = (b.x - a.x) / (float)steps;
    float dstepy = (b.y - a.y) / (float)steps;
    float rad = self.strokeSize / 2;
    
    for (int ii = 0; ii < steps; ii++) {
        float decay = sqrtf(sqrtf(ii / (float)steps));
        float istepx = dstepx * decay + previousStrokeDX * (1.0 - decay);
        float istepy = dstepy * decay + previousStrokeDY * (1.0 - decay);
        float x = a.x - rad + istepx * ii;
        float y = a.y - rad + istepy * ii;
        CGRect r = CGRectMake(x, y, rad * 2, rad * 2);
        CGContextFillEllipseInRect(pc, r);
    }
    
    previousStrokeDX = dstepx;
    previousStrokeDY = dstepy;
    
    CGRect aRect = CGRectMake(a.x - rad, a.y - rad, rad * 2, rad * 2);
    CGRect bRect = CGRectMake(b.x - rad, b.y - rad, rad * 2, rad * 2);

    [self setNeedsDisplayInRect: CGRectUnion(aRect, bRect)];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint p = [[touches anyObject] locationInView: self];
    [self addStrokeFromPoint:p toPoint:p];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint p = [[touches anyObject] previousLocationInView: self];
    CGPoint q = [[touches anyObject] locationInView: self];
    [self addStrokeFromPoint:p toPoint:q];
    [self touchesMovedExtendStroke: q withTimestamp: [event timestamp]];
}

- (void)touchesMovedExtendStroke:(CGPoint)p withTimestamp:(NSTimeInterval)t
{
 
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint p = [[touches anyObject] previousLocationInView: self];
    CGPoint q = [[touches anyObject] locationInView: self];
    [self addStrokeFromPoint:p toPoint:q];
}

@end
