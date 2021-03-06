//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "Cryptography.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageSender.h"
#import "OWSPrimaryStorage.h"
#import "OWSUnitTestEnvironment.h"
#import "SSKBaseTest.h"
#import "SSKProto.pb.h"
#import "TSGroupThread.h"
#import "TSNetworkManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSMessagesManager (Testing)

// Private init for stubbing dependencies

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(OWSPrimaryStorage *)storageManager
                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
                       identityManager:(OWSIdentityManager *)identityManager
                         messageSender:(OWSMessageSender *)messageSender;

// private method we are testing
- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)messageEnvelope withSyncMessage:(SSKProtoSyncMessage *)syncMessage;

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)messageEnvelope withDataMessage:(SSKProtoDataMessage *)dataMessage;

@end

@interface TSMessagesManagerTest : SSKBaseTest

@end

@implementation TSMessagesManagerTest

- (TSMessagesManager *)messagesManagerWithSender:(OWSMessageSender *)messageSender
{
    return [[TSMessagesManager alloc] initWithNetworkManager:[OWSFakeNetworkManager new]
                                              storageManager:[OWSPrimaryStorage sharedManager]
                                          callMessageHandler:[OWSFakeCallMessageHandler new]
                                             contactsManager:[OWSFakeContactsManager new]
                                             identityManager:[OWSIdentityManager sharedManager]
                                               messageSender:messageSender];
}

- (void)setUp
{
    [super setUp];
    
    [OWSUnitTestEnvironment ensureSetup];
}

- (void)testIncomingSyncContactMessage
{
    XCTestExpectation *messageWasSent = [self expectationWithDescription:@"message was sent"];
    TSMessagesManager *messagesManager =
        [self messagesManagerWithSender:[[OWSFakeMessageSender alloc] initWithExpectation:messageWasSent]];

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];
    SSKProtoSyncMessageBuilder *messageBuilder = [SSKProtoSyncMessageBuilder new];
    SSKProtoSyncMessageRequestBuilder *requestBuilder = [SSKProtoSyncMessageRequestBuilder new];
    [requestBuilder setType:SSKProtoSyncMessageRequestTypeGroups];
    [messageBuilder setRequest:[requestBuilder build]];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withSyncMessage:[messageBuilder build]];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     NSLog(@"No message submitted.");
                                 }];
}

- (void)testGroupUpdate
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = SSKProtoGroupContextTypeUpdate;

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group Name", groupThread.name);
}

- (void)testGroupUpdateWithAvatar
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];


    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = SSKProtoGroupContextTypeUpdate;

    SSKProtoAttachmentPointerBuilder *attachmentBuilder = [SSKProtoAttachmentPointerBuilder new];
    attachmentBuilder.id = 1234;
    attachmentBuilder.contentType = @"image/png";
    attachmentBuilder.key = [NSData new];
    attachmentBuilder.size = 123;
    groupContextBuilder.avatar = [attachmentBuilder build];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group with Avatar Name", groupThread.name);
}

- (void)testUnknownGroupMessageIsIgnored
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupIdData:groupIdData];

    // Sanity check
    XCTAssertEqual(0, groupThread.numberOfInteractions);

    TSMessagesManager *messagesManager = [self messagesManagerWithSender:[OWSFakeMessageSender new]];

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;

    // e.g. some future feature sent from another device that we don't yet support.
    groupContextBuilder.type = 666;

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder build];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withDataMessage:[messageBuilder build]];

    XCTAssertEqual(0, groupThread.numberOfInteractions);
}

@end

NS_ASSUME_NONNULL_END
