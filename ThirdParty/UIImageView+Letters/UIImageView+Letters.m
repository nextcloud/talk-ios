//
//  UIImageView+Letters.m
//
//  Created by Tom Bachant on 6/17/14.
//  Copyright (c) 2014 Tom Bachant. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "UIImageView+Letters.h"
#import <CommonCrypto/CommonDigest.h>

// This multiplier sets the font size based on the view bounds
static const CGFloat kFontResizingProportion = 0.5f;

@interface UIImageView (LettersPrivate)

- (UIImage *)imageSnapshotFromText:(NSString *)text backgroundColor:(UIColor *)color circular:(BOOL)isCircular textAttributes:(NSDictionary *)attributes;

@end

@implementation UIImageView (Letters)

- (void)setImageWithString:(NSString *)string {
    [self setImageWithString:string color:nil circular:NO textAttributes:nil];
}

- (void)setImageWithString:(NSString *)string color:(UIColor *)color {
    [self setImageWithString:string color:color circular:NO textAttributes:nil];
}

- (void)setImageWithString:(NSString *)string color:(UIColor *)color circular:(BOOL)isCircular {
    [self setImageWithString:string color:color circular:isCircular textAttributes:nil];
}

- (void)setImageWithString:(NSString *)string color:(UIColor *)color circular:(BOOL)isCircular fontName:(NSString *)fontName {
    [self setImageWithString:string color:color circular:isCircular textAttributes:@{
                                                                                     NSFontAttributeName:[self fontForFontName:fontName],
                                                                                     NSForegroundColorAttributeName: [UIColor whiteColor]
                                                                                     }];
}

- (void)setImageWithString:(NSString *)string color:(UIColor *)color circular:(BOOL)isCircular textAttributes:(NSDictionary *)textAttributes {
    if (!textAttributes) {
        textAttributes = @{
                           NSFontAttributeName: [self fontForFontName:nil],
                           NSForegroundColorAttributeName: [UIColor whiteColor]
                           };
    }
    
    NSMutableString *displayString = [NSMutableString stringWithString:@""];
    
    NSMutableArray *words = [[string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] mutableCopy];
    
    //
    // Get first letter of the first word
    //
    if ([words count]) {
        NSString *firstWord = [words firstObject];
        if ([firstWord length]) {
            // Get character range to handle emoji (emojis consist of 2 characters in sequence)
            NSRange firstLetterRange = [firstWord rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 1)];
            [displayString appendString:[firstWord substringWithRange:firstLetterRange]];
        }
    }
    
    UIColor *backgroundColor = color ? color : [self colorFromString:string];

    self.image = [self imageSnapshotFromText:[displayString uppercaseString] backgroundColor:backgroundColor circular:isCircular textAttributes:textAttributes];
}

#pragma mark - Helpers

- (UIFont *)fontForFontName:(NSString *)fontName {
    
    CGFloat fontSize = CGRectGetWidth(self.bounds) * kFontResizingProportion;
    if (fontName) {
        return [UIFont fontWithName:fontName size:fontSize];
    }
    else {
        return [UIFont boldSystemFontOfSize:fontSize];
    }
    
}

- (UIColor *)randomColor {
    
    srand48(arc4random());
    
    float red = 0.0;
    while (red < 0.1 || red > 0.84) {
        red = drand48();
    }
    
    float green = 0.0;
    while (green < 0.1 || green > 0.84) {
        green = drand48();
    }
    
    float blue = 0.0;
    while (blue < 0.1 || blue > 0.84) {
        blue = drand48();
    }
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0f];
}

- (UIColor *)colorFromString:(NSString *)string {
    const char *cStr = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (int)strlen(cStr), result );
    NSInteger seedMd5Int = [[NSString stringWithFormat:
                        @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                        result[0], result[1], result[2], result[3],
                        result[4], result[5], result[6], result[7],
                        result[8], result[9], result[10], result[11],
                        result[12], result[13], result[14], result[15]
                        ] hash];
    
    int maxRange = INT_MAX;
    
    float h = (float) (seedMd5Int / maxRange * 360);
    float s = 90.0f;
    float l = 65.0f;
    float alpha = 1.0f;
        
    if (s < 0.0f || s > 100.0f) {
        NSLog(@"Color parameter outside of expected range - Saturation");
    }
    
    if (l < 0.0f || l > 100.0f) {
        NSLog(@"Color parameter outside of expected range - Luminance");
    }
    
    if (alpha < 0.0f || alpha > 1.0f) {
        NSLog(@"Color parameter outside of expected range - Alpha");
    }
    
    //  Formula needs all values between 0 - 1.
    
    h = fmodf(h, 360.0f);//h % 360;
    h = h / 360.0f;
    s = s / 100.0f;
    l = l / 100.0f;
    
    float q;
    
    if (l < 0.5) {
        q = l * (1 + s);
    } else {
        q = (l + s) - (s * l);
    }
    
    float p = 2 * l - q;
    
    int r = round(MAX(0, [self HueToRGBp:p q:q h:h + (1.0f / 3.0f)] * 256));
    int g = round(MAX(0, [self HueToRGBp:p q:q h:h] * 256));
    int b = round(MAX(0, [self HueToRGBp:p q:q h:h - (1.0f / 3.0f)] * 256));
    
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];
}

- (float)HueToRGBp:(float)p q:(float)q h:(float)h {
    if (h < 0) {
        h += 1;
    }
    
    if (h > 1) {
        h -= 1;
    }
    
    if (6 * h < 1) {
        return p + ((q - p) * 6 * h);
    }
    
    if (2 * h < 1) {
        return q;
    }
    
    if (3 * h < 2) {
        return p + ((q - p) * 6 * ((2.0f / 3.0f) - h));
    }
    
    return p;
}

- (UIImage *)imageSnapshotFromText:(NSString *)text backgroundColor:(UIColor *)color circular:(BOOL)isCircular textAttributes:(NSDictionary *)textAttributes {
    
    CGFloat scale = [UIScreen mainScreen].scale;
    
    CGSize size = self.bounds.size;
    if (self.contentMode == UIViewContentModeScaleToFill ||
        self.contentMode == UIViewContentModeScaleAspectFill ||
        self.contentMode == UIViewContentModeScaleAspectFit ||
        self.contentMode == UIViewContentModeRedraw)
    {
        size.width = floorf(size.width * scale) / scale;
        size.height = floorf(size.height * scale) / scale;
    }
    
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (isCircular) {
        //
        // Clip context to a circle
        //
        CGPathRef path = CGPathCreateWithEllipseInRect(self.bounds, NULL);
        CGContextAddPath(context, path);
        CGContextClip(context);
        CGPathRelease(path);
    }
    
    //
    // Fill background of context
    //
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    
    //
    // Draw text in the context
    //
    CGSize textSize = [text sizeWithAttributes:textAttributes];
    CGRect bounds = self.bounds;
    
    [text drawInRect:CGRectMake(bounds.size.width/2 - textSize.width/2,
                                bounds.size.height/2 - textSize.height/2,
                                textSize.width,
                                textSize.height)
      withAttributes:textAttributes];
    
    UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return snapshot;
}

@end
