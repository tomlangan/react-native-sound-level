#import "RNAudioRecord.h"
#import "RNSoundLevelModule.h"
#import <React/RCTConvert.h>
#import <React/RCTBridge.h>
#import <React/RCTUtils.h>
#import <React/RCTEventDispatcher.h>
#import <AVFoundation/AVFoundation.h>

@implementation RNAudioRecord

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(init:(NSDictionary *) options) {
    RCTLogInfo(@"init");
    _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 44100 : [options[@"sampleRate"] doubleValue];
    _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
    _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
    _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
    _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
    _recordState.mDataFormat.mFramesPerPacket   = 1;
    _recordState.mDataFormat.mReserved          = 0;
    _recordState.mDataFormat.mFormatID          = kAudioFormatLinearPCM;
    _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);

    
    _recordState.bufferByteSize = 2048;
    _recordState.mSelf = self;
    
    NSString *fileName = options[@"wavFile"] == nil ? @"audio.wav" : options[@"wavFile"];
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    _filePath = [NSString stringWithFormat:@"%@/%@", docDir, fileName];
}

RCT_EXPORT_METHOD(start) {
    RCTLogInfo(@"start");

    // most audio players set session category to "Playback", record won't work in this mode
    // therefore set session category to "Record" before recording
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];

    _recordState.mIsRunning = true;
    _recordState.mCurrentPacket = 0;
    
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)_filePath, NULL);
    AudioFileCreateWithURL(url, kAudioFileWAVEType, &_recordState.mDataFormat, kAudioFileFlags_EraseFile, &_recordState.mAudioFile);
    CFRelease(url);
    
    AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
    }
    AudioQueueStart(_recordState.mQueue, NULL);
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"stop");
    if (_recordState.mIsRunning) {
        _recordState.mIsRunning = false;
        AudioQueueStop(_recordState.mQueue, true);
        AudioQueueDispose(_recordState.mQueue, true);
        AudioFileClose(_recordState.mAudioFile);
    }
    resolve(_filePath);
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
    RCTLogInfo(@"file path %@", _filePath);
    RCTLogInfo(@"file size %llu", fileSize);
}

void HandleInputBuffer(void *inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *inPacketDesc) {
    AQRecordState* pRecordState = (AQRecordState *)inUserData;
    
    if (!pRecordState->mIsRunning) {
        return;
    }
    
    if (AudioFileWritePackets(pRecordState->mAudioFile,
                              false,
                              inBuffer->mAudioDataByteSize,
                              inPacketDesc,
                              pRecordState->mCurrentPacket,
                              &inNumPackets,
                              inBuffer->mAudioData
                              ) == noErr) {
        pRecordState->mCurrentPacket += inNumPackets;
    }
    
    short *samples = (short *) inBuffer->mAudioData;
    long nsamples = inBuffer->mAudioDataByteSize;
    NSData *data = [NSData dataWithBytes:samples length:nsamples];
    NSString *str = [data base64EncodedStringWithOptions:0];
    [pRecordState->mSelf sendEventWithName:@"data" body:str];
    
    AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"data"];
}

- (void)dealloc {
    RCTLogInfo(@"dealloc");
    AudioQueueDispose(_recordState.mQueue, true);
}

@end


@implementation RNSoundLevelModule {

  AVAudioRecorder *_audioRecorder;
  id _progressUpdateTimer;
  int _frameId;
  int _progressUpdateInterval;
  NSDate *_prevProgressUpdateTime;
  AVAudioSession *_recordSession;
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

- (void)sendProgressUpdate {
  if (!_audioRecorder || !_audioRecorder.isRecording) {
    return;
  }

  if (_prevProgressUpdateTime == nil ||
   (([_prevProgressUpdateTime timeIntervalSinceNow] * -1000.0) >= _progressUpdateInterval)) {
      _frameId++;
      NSMutableDictionary *body = [[NSMutableDictionary alloc] init];
      [body setObject:[NSNumber numberWithFloat:_frameId] forKey:@"id"];

      [_audioRecorder updateMeters];
      float _currentLevel = [_audioRecorder averagePowerForChannel: 0];
      [body setObject:[NSNumber numberWithFloat:_currentLevel] forKey:@"value"];
      [body setObject:[NSNumber numberWithFloat:_currentLevel] forKey:@"rawValue"];

      [self.bridge.eventDispatcher sendAppEventWithName:@"frame" body:body];

    _prevProgressUpdateTime = [NSDate date];
  }
}

- (void)stopProgressTimer {
  [_progressUpdateTimer invalidate];
}

- (void)startProgressTimer:(int)monitorInterval {
  _progressUpdateInterval = monitorInterval;

  [self stopProgressTimer];

  _progressUpdateTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(sendProgressUpdate)];
  [_progressUpdateTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

RCT_EXPORT_METHOD(start:(int)monitorInterval samplingRate:(float)sampleRate)
{
  NSLog(@"Start Monitoring");
  _prevProgressUpdateTime = nil;
  [self stopProgressTimer];

  NSDictionary *recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:
          [NSNumber numberWithInt:AVAudioQualityLow], AVEncoderAudioQualityKey,
          [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
          [NSNumber numberWithInt:1], AVNumberOfChannelsKey,
          [NSNumber numberWithFloat:sampleRate], AVSampleRateKey,
          nil];

  NSError *error = nil;

  _recordSession = [AVAudioSession sharedInstance];
  [_recordSession setCategory:AVAudioSessionCategoryMultiRoute error:nil];

  NSURL *_tempFileUrl = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"temp"]];

  _audioRecorder = [[AVAudioRecorder alloc]
                initWithURL:_tempFileUrl
                settings:recordSettings
                error:&error];

  _audioRecorder.delegate = self;

  if (error) {
      NSLog(@"error: %@", [error localizedDescription]);
    } else {
      [_audioRecorder prepareToRecord];
  }

  _audioRecorder.meteringEnabled = YES;

  [self startProgressTimer:monitorInterval];
  [_recordSession setActive:YES error:nil];
  [_audioRecorder record];
}

RCT_EXPORT_METHOD(stop)
{
  [_audioRecorder stop];
  [_recordSession setCategory:AVAudioSessionCategoryPlayback error:nil];
  _prevProgressUpdateTime = nil;
}

@end