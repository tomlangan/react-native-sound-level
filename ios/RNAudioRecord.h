#import <AVFoundation/AVFoundation.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTLog.h>
#import <React/RCTBridgeModule.h>
#import <AVFoundation/AVFoundation.h>


#define kNumberBuffers 3

typedef struct {
    __unsafe_unretained id      mSelf;
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberBuffers];
    AudioFileID                 mAudioFile;
    UInt32                      bufferByteSize;
    SInt64                      mCurrentPacket;
    bool                        mIsRunning;
} AQRecordState;

@interface RNAudioRecord : RCTEventEmitter <RCTBridgeModule>
    @property (nonatomic, assign) AQRecordState recordState;
    @property (nonatomic, strong) NSString* filePath;
@end

@interface RNSoundLevelModule : NSObject <RCTBridgeModule, AVAudioRecorderDelegate>

@end
