//
//  ALPHATheme.m
//  Alpha
//
//  Created by Dal Rupnik on 01/12/14.
//  Copyright (c) 2014 Unified Sense. All rights reserved.
//

#import "ALPHANavigationController.h"

#import "UIImage+Creation.h"

#import "UIApplication+ALPHAPrivate.h"

#import "ALPHATheme.h"
#import "FLEXUtility.h"
#import "ALPHAManager+Private.h"

@implementation ALPHATheme

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        self.fontFamily = @"Menlo";
        
        self.topMargin = 2.0;
    }
    
    return self;
}

+ (instancetype)theme
{
    return [[[self class] alloc] init];
}

- (void)applyInWindow:(UIWindow *)window
{
    window.tintColor = self.tintColor;
    
    [[UINavigationBar appearanceWhenContainedIn:[ALPHANavigationController class], nil] setTitleTextAttributes:@{ NSFontAttributeName : [UIFont fontWithName:self.fontFamily size:17.0], NSForegroundColorAttributeName : self.tintColor }];
    
    [[UINavigationBar appearanceWhenContainedIn:[ALPHANavigationController class], nil] setBackgroundImage:[UIImage alpha_imageWithColor:self.highlightedBackgroundColor] forBarMetrics:UIBarMetricsDefault];
    [[UINavigationBar appearanceWhenContainedIn:[ALPHANavigationController class], nil] setTranslucent:NO];
    [[UINavigationBar appearanceWhenContainedIn:[ALPHANavigationController class], nil] setShadowImage:[UIImage alpha_imageWithColor:self.selectedBackgroundColor]];
    
    [[UIBarButtonItem appearanceWhenContainedIn:[ALPHANavigationController class], nil] setTitleTextAttributes:@{ NSFontAttributeName : [UIFont fontWithName:self.fontFamily size:14.0] } forState:UIControlStateNormal];
    
    //id statusBar = [[UIApplication sharedApplication] statusBar];
    
    //[statusBar performSelector:NSSelectorFromString(@"setForegroundColor:") withObject:self.tintColor];
}

- (UIFont *)themeFontOfSize:(CGFloat)size
{
    return [UIFont fontWithName:self.fontFamily size:size];
}

- (UIFont *)themeFontWithFont:(UIFont *)font
{
    return [self themeFontOfSize:font.pointSize];
}

@end
