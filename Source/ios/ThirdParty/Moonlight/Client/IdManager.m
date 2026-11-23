//
//  IdManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/31/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "IdManager.h"

@implementation IdManager

+ (NSString*) getUniqueId {
    @synchronized (self) {
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        NSString *uniqueId = [prefs stringForKey:@"apollo.clientId"];
        if (uniqueId == nil) {
            uniqueId = [IdManager generateUniqueId];
            [prefs setObject:uniqueId forKey:@"apollo.clientId"];
        }
        return uniqueId;
    }
}

+ (NSString*) generateUniqueId {
    UInt64 uuidLong = ((UInt64) arc4random() << 32) | arc4random();
    return [NSString stringWithFormat:@"%016llx", uuidLong];
}

@end
