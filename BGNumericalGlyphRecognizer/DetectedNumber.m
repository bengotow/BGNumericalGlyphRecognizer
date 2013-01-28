//
//  DetectedNumber.m
//  SketchMath
//
//  Created by Ben Gotow on 4/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "DetectedNumber.h"

@implementation DetectedNumber

@synthesize rect, center, value, valueSecondary, view, glyphName;

- (id)initWithValue:(NSString*)v
{
    self = [super init];
    if (self) {
        self.value = v;
    }
    return self;
}

- (BOOL)isMatchForNumber:(NSString*)number
{
    if (([number isEqualToString: value]) || ([number isEqualToString: valueSecondary]))
        return YES;
    
    // if we're a partial for a 4 and the user's answer was 4, that's probably a match...
    if ([[glyphName substringToIndex:1] isEqualToString:@"p"]) {
        if (([[glyphName substringWithRange: NSMakeRange(1, 1)] isEqualToString:@"4"]) && ([number isEqualToString:@"2"]))
            return YES;
        if (([[glyphName substringWithRange: NSMakeRange(1, 1)] isEqualToString:@"5"]) && ([number isEqualToString:@"5"]))
            return YES;
    }
    return NO;
}

@end
