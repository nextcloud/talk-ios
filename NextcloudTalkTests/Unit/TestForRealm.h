//
//  TestForRealm.h
//  NextcloudTalkTests
//
//  Created by Marcel Müller on 25.01.24.
//

#import <Foundation/Foundation.h>
#import <Realm/RLMRealm.h>

NS_ASSUME_NONNULL_BEGIN

@interface TestForRealm : NSObject

- (RLMRealm *)setupRealm;

@end

NS_ASSUME_NONNULL_END
