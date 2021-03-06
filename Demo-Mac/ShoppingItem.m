//
//  ShoppingItem.m
//  CouchCocoa
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "ShoppingItem.h"

@implementation ShoppingItem

@dynamic check, text, created_at;

- (NSDictionary*) propertiesToSave {
    if (self.created_at == nil)
        self.created_at = [NSDate date];
    return [super propertiesToSave];
}

@end
