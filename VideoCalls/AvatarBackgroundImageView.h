//
//  AvatarBackgroundImageView.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.12.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GradientView : UIView

@property (nonatomic, strong, readonly) CAGradientLayer *layer;

@end

@interface AvatarBackgroundImageView : UIImageView

@property (nonatomic, strong)  GradientView *gradientView;

@end

NS_ASSUME_NONNULL_END
