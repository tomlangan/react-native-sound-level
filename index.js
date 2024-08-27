'use strict'

import { NativeModules, NativeAppEventEmitter, Platform } from 'react-native'

var SoundLevelModule = NativeModules.RNSoundLevelModule;

var SoundLevel = {
  timer: null,

  start: function (_monitorConfig = 250) {
    const monitorConfig = {
      monitorInterval: 250,
      samplingRate: 22050,
    }

    if (typeof _monitorConfig === 'number') {
      monitorConfig.monitorInterval = _monitorConfig
    }

    if (this.frameSubscription) {
      this.frameSubscription.remove()
    }

    
    this.frameSubscription = NativeAppEventEmitter.addListener(
      'frame',
      data => {
        if (this.onNewFrame) {
          this.onNewFrame(data)
        }
      }
    )

    // Monitoring interval not supported for Android yet. Feel free to add and do a pull request. :)
    return  SoundLevelModule.start(monitorConfig.monitorInterval, monitorConfig.samplingRate);
  },

  stop: function () {
    if (this.frameSubscription) {
      this.frameSubscription.remove()
    }

    if (this.timer) {
      clearInterval(this.timer)
    }

    return SoundLevelModule.stop()
  }
}

module.exports = SoundLevel
