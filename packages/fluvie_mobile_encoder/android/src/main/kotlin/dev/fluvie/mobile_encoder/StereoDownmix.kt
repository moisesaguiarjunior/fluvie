package dev.fluvie.mobile_encoder

import android.media.AudioFormat

/** Routes interleaved PCM to stereo using the decoder's positional channel mask. */
internal class StereoDownmix(channels: Int, channelMask: Int) {
  private val left = FloatArray(channels)
  private val right = FloatArray(channels)

  init {
    val mask = if (channelMask != 0 && Integer.bitCount(channelMask) == channels) {
      channelMask
    } else {
      canonicalMask(channels)
    }
    if (channels == 1) {
      left[0] = 1f
      right[0] = 1f
    } else {
      var positions = mask
      var index = 0
      while (positions != 0) {
        val position = Integer.lowestOneBit(positions)
        when (position) {
          AudioFormat.CHANNEL_OUT_FRONT_LEFT -> left[index] = 1f
          AudioFormat.CHANNEL_OUT_FRONT_RIGHT -> right[index] = 1f
          AudioFormat.CHANNEL_OUT_FRONT_CENTER,
          AudioFormat.CHANNEL_OUT_BACK_CENTER,
          AudioFormat.CHANNEL_OUT_TOP_CENTER,
          AudioFormat.CHANNEL_OUT_TOP_FRONT_CENTER,
          AudioFormat.CHANNEL_OUT_TOP_BACK_CENTER -> {
            left[index] = DOWNMIX_GAIN
            right[index] = DOWNMIX_GAIN
          }
          AudioFormat.CHANNEL_OUT_FRONT_LEFT_OF_CENTER,
          AudioFormat.CHANNEL_OUT_BACK_LEFT,
          AudioFormat.CHANNEL_OUT_SIDE_LEFT,
          AudioFormat.CHANNEL_OUT_TOP_FRONT_LEFT,
          AudioFormat.CHANNEL_OUT_TOP_BACK_LEFT,
          AudioFormat.CHANNEL_OUT_TOP_SIDE_LEFT ->
            left[index] = DOWNMIX_GAIN
          AudioFormat.CHANNEL_OUT_FRONT_RIGHT_OF_CENTER,
          AudioFormat.CHANNEL_OUT_BACK_RIGHT,
          AudioFormat.CHANNEL_OUT_SIDE_RIGHT,
          AudioFormat.CHANNEL_OUT_TOP_FRONT_RIGHT,
          AudioFormat.CHANNEL_OUT_TOP_BACK_RIGHT,
          AudioFormat.CHANNEL_OUT_TOP_SIDE_RIGHT ->
            right[index] = DOWNMIX_GAIN
        }
        // The stereo mix leaves out the LFE channel.
        positions = positions xor position
        index++
      }
    }
  }

  fun mix(samples: ShortArray, source: Int, target: FloatArray, dest: Int, gain: Float) {
    var leftSample = 0f
    var rightSample = 0f
    for (channel in left.indices) {
      val sample = samples[source + channel] / 32768f
      leftSample += sample * left[channel]
      rightSample += sample * right[channel]
    }
    target[dest] += leftSample * gain
    target[dest + 1] += rightSample * gain
  }

  private companion object {
    fun canonicalMask(channels: Int): Int = when (channels) {
      3 -> AudioFormat.CHANNEL_OUT_STEREO or AudioFormat.CHANNEL_OUT_FRONT_CENTER
      4 -> AudioFormat.CHANNEL_OUT_QUAD
      5 -> AudioFormat.CHANNEL_OUT_QUAD or AudioFormat.CHANNEL_OUT_FRONT_CENTER
      6 -> AudioFormat.CHANNEL_OUT_5POINT1
      7 -> AudioFormat.CHANNEL_OUT_5POINT1 or AudioFormat.CHANNEL_OUT_BACK_CENTER
      8 -> AudioFormat.CHANNEL_OUT_7POINT1_SURROUND
      else -> AudioFormat.CHANNEL_OUT_STEREO
    }

    const val DOWNMIX_GAIN = 0.70710677f
  }
}
