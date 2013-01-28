//
//  DetectedNumber.h
//  SketchMath
//
//  Created by Ben Gotow on 4/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetectedNumber : NSObject

@property (nonatomic, assign) CGPoint center; 
@property (nonatomic, assign) CGRect rect;
@property (nonatomic, retain) UIView * view;

@property (nonatomic, retain) NSString * glyphName;

@property (nonatomic, retain) NSString * value;
@property (nonatomic, retain) NSString * valueSecondary;

- (id)initWithValue:(NSString*)v;
- (BOOL)isMatchForNumber:(NSString*)number;

@end
