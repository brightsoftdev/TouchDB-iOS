//
//  TDDatabase_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "TDDatabase.h"
#import "TDBody.h"
#import "TDRevision.h"
#import "TDBlobStore.h"
#import "TDInternal.h"
#import "Test.h"



#if DEBUG


NSString* kPath = @"/tmp/touchdb_test.sqlite3";


static TDDatabase* createDB(void) {
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: kPath];
    CAssert([db open]);
    CAssert(![db error]);
    return db;
}


static NSDictionary* userProperties(NSDictionary* dict) {
    NSMutableDictionary* user = $mdict();
    for (NSString* key in dict) {
        if (![key hasPrefix: @"_"])
            [user setObject: [dict objectForKey: key] forKey: key];
    }
    return user;
}

TestCase(TDDatabase_CRUD) {
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", $object(1)}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDStatus status;
    rev1 = [db putRevision: rev1 prevRevisionID: nil status: &status];
    CAssertEq(status, 201);
    Log(@"Created: %@", rev1);
    CAssert(rev1.docID.length >= 10);
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    TDRevision* readRev = [db getDocumentWithID: rev1.docID];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [[readRev.properties mutableCopy] autorelease];
    [props setObject: @"updated!" forKey: @"status"];
    doc = [TDBody bodyWithProperties: props];
    TDRevision* rev2 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDRevision* rev2Input = rev2;
    rev2 = [db putRevision: rev2 prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, 201);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putRevision: rev2Input prevRevisionID: rev1.revID status: &status]);
    CAssertEq(status, 409);
    
    // Delete it:
    TDRevision* revD = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted: YES] autorelease];
    revD = [db putRevision: revD prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, 200);
    CAssertEqual(revD.docID, rev2.docID);
    CAssert([revD.revID hasPrefix: @"3-"]);
    
    // Read it back (should fail):
    readRev = [db getDocumentWithID: revD.docID];
    CAssertNil(readRev);
    
    TDRevisionList* changes = [db changesSinceSequence: 0 options: NULL];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    NSArray* history = [db getRevisionHistory: revD];
    Log(@"History = %@", history);
    CAssertEqual(history, $array(revD, rev2, rev1));
    
    CAssert([db close]);
}


static void verifyHistory(TDDatabase* db, TDRevision* rev, NSArray* history) {
    TDRevision* gotRev = [db getDocumentWithID: rev.docID];
    CAssertEqual(gotRev, rev);
    CAssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev];
    CAssertEq(revHistory.count, history.count);
    for (NSUInteger i=0; i<history.count; i++) {
        TDRevision* hrev = [revHistory objectAtIndex: i];
        CAssertEqual(hrev.docID, rev.docID);
        CAssertEqual(hrev.revID, [history objectAtIndex: i]);
        CAssert(!hrev.deleted);
    }
}


TestCase(TDDatabase_RevTree) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    TDRevision* rev = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"4-foxy" deleted: NO] autorelease];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = $array(rev.revID, @"3-thrice", @"2-too", @"1-won");
    TDStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    CAssertEq(status, 201);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, rev, history);
    
    TDRevision* conflict = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"5-epsilon" deleted: NO] autorelease];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    history = $array(conflict.revID, @"4-delta", @"3-gamma", @"2-too", @"1-won");
    status = [db forceInsert: conflict revisionHistory: history source: nil];
    CAssertEq(status, 201);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, conflict, history);
    
    // Fetch one of those phantom revisions with no body:
    TDRevision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-too"];
    CAssertEqual(rev2.docID, rev.docID);
    CAssertEqual(rev2.revID, @"2-too");
    CAssertEqual(rev2.body, nil);
    
    // Make sure no duplicate rows were inserted for the common revisions:
    CAssertEq(db.lastSequence, 7u);
    
    // Make sure the revision with the higher revID wins the conflict:
    TDRevision* current = [db getDocumentWithID: rev.docID];
    CAssertEqual(current, conflict);
}


TestCase(TDDatabase_Attachments) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    TDBlobStore* attachments = db.attachmentStore;

    CAssertEq(attachments.count, 0u);
    CAssertEqual(attachments.allKeys, $array());
    
    // Add a revision and an attachment to it:
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties:$mdict({@"foo", $object(1)},
                                                                      {@"bar", $false})]
            prevRevisionID: nil status: &status];
    CAssertEq(status, 201);
    
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    CAssert([db insertAttachment: attach1 forSequence: rev1.sequence named: @"attach"]);
    
    CAssertEqual([db getAttachmentForSequence: rev1.sequence
                                        named: @"attach"
                                       status: &status], attach1);
    CAssertEq(status, 200);

    // Add a second revision of the same document:
    TDRevision* rev2;
    rev2 = [db putRevision: [TDRevision revisionWithProperties:$mdict({@"_id", rev1.docID},
                                                                      {@"foo", $object(2)},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, 201);
    
    NSData* attach2 = [@"And this is attach2's body" dataUsingEncoding: NSUTF8StringEncoding];
    CAssert([db insertAttachment: attach2 forSequence: rev2.sequence named: @"attach"]);
    
    CAssertEqual([db getAttachmentForSequence: rev2.sequence
                                        named: @"attach"
                                       status: &status], attach2);
    CAssertEq(status, 200);
    
    // Examine the attachment store:
    CAssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [TDBlobStore keyDataForBlob: attach1],
                                             [TDBlobStore keyDataForBlob: attach2], nil];
    CAssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    CAssertEq([db compact], 200);
    CAssertEq([db garbageCollectAttachments], 1);
    CAssertEq(attachments.count, 1u);
    CAssertEqual(attachments.allKeys, $array([TDBlobStore keyDataForBlob: attach2]));
}


TestCase(TDDatabase_ReplicatorSequences) {
    RequireTestCase(TDDatabase_CRUD);
    TDDatabase* db = createDB();
    NSURL* remote = [NSURL URLWithString: @"http://iriscouch.com/"];
    CAssertNil([db lastSequenceWithRemoteURL: remote push: NO]);
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"lastpull" withRemoteURL: remote push: NO];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"lastpull");
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"newerpull" withRemoteURL: remote push: NO];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"newerpull");
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"lastpush" withRemoteURL: remote push: YES];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"newerpull");
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: YES], @"lastpush");
}


TestCase(TDDatabase) {
    RequireTestCase(TDDatabase_CRUD);
    RequireTestCase(TDDatabase_RevTree);
    RequireTestCase(TDDatabase_Attachments);
    RequireTestCase(TDDatabase_ReplicatorSequences);
}


#endif //DEBUG
