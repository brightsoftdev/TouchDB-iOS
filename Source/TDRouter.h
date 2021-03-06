//
//  TDRouter.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDServer, TDResponse, TDBody;


extern NSString* const kTDVersionString;


typedef void (^OnResponseReadyBlock)(TDResponse*);
typedef void (^OnDataAvailableBlock)(NSData*);
typedef void (^OnFinishedBlock)();


@interface TDRouter : NSObject
{
    @private
    TDServer* _server;
    NSURLRequest* _request;
    NSDictionary* _queries;
    TDResponse* _response;
    TDDatabase* _db;
    BOOL _waiting;
    BOOL _responseSent;
    OnResponseReadyBlock _onResponseReady;
    OnDataAvailableBlock _onDataAvailable;
    OnFinishedBlock _onFinished;
    BOOL _longpoll;
}

- (id) initWithServer: (TDServer*)server request: (NSURLRequest*)request;

@property (copy) OnResponseReadyBlock onResponseReady;
@property (copy) OnDataAvailableBlock onDataAvailable;
@property (copy) OnFinishedBlock onFinished;

@property (readonly) TDResponse* response;

- (void) start;
- (void) stop;

@end



@interface TDResponse : NSObject
{
    @private
    int _status;
    NSMutableDictionary* _headers;
    TDBody* _body;
}

@property int status;
@property (copy) NSMutableDictionary* headers;
@property (retain) TDBody* body;
@property (copy) id bodyObject;

- (void) setValue: (NSString*)value ofHeader: (NSString*)header;

@end