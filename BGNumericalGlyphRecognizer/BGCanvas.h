//
//  SimplePaintView.h
//  ScribbleMath
//
//  Created by Ben Gotow on 6/6/12.
//  Copyright (c) 2012 Foundry376. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BGCanvas : UIView
{
    CGLayerRef paintLayer;
    
    float previousStrokeDX;
    float previousStrokeDY;
}

@property (nonatomic, retain) UIColor * strokeColor;
@property (nonatomic, assign) float strokeSize;

- (id)initWithFrame:(CGRect)frame;
- (void)awakeFromNib;
- (void)setup;
- (void)clear;
- (void)drawRect:(CGRect)rect;
- (void)addStrokeFromPoint:(CGPoint)a toPoint:(CGPoint)b;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMovedExtendStroke:(CGPoint)p withTimestamp:(NSTimeInterval)t;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;

@end
