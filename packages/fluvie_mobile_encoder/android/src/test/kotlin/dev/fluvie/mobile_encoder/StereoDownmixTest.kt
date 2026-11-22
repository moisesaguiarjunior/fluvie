package dev.fluvie.mobile_encoder

import android.media.AudioFormat
import org.junit.Assert.assertEquals
import org.junit.Test

class StereoDownmixTest {
  @Test
  fun routesSequentialTonesIn512() {
    val expected = bed + listOf(attenuatedLeft, attenuatedRight)
    assertRouting(AudioFormat.CHANNEL_OUT_5POINT1POINT2, expected)
    // WAVE also labels 5.1.2 with top-front rather than top-side positions.
    val waveMask = AudioFormat.CHANNEL_OUT_5POINT1 or
      AudioFormat.CHANNEL_OUT_TOP_FRONT_LEFT or AudioFormat.CHANNEL_OUT_TOP_FRONT_RIGHT
    assertRouting(waveMask, expected)
  }

  @Test
  fun routesSequentialTonesIn514() {
    assertRouting(
      AudioFormat.CHANNEL_OUT_5POINT1POINT4,
      bed + listOf(attenuatedLeft, attenuatedRight, attenuatedLeft, attenuatedRight),
    )
  }

  @Test
  fun sendsCenteredHeightChannelsToBothSides() {
    for (mask in listOf(
      AudioFormat.CHANNEL_OUT_TOP_CENTER,
      AudioFormat.CHANNEL_OUT_TOP_FRONT_CENTER,
      AudioFormat.CHANNEL_OUT_TOP_BACK_CENTER,
    )) {
      assertRouting(AudioFormat.CHANNEL_OUT_STEREO or mask, listOf(left, right, center))
    }
  }

  private fun assertRouting(mask: Int, expected: List<Pair<Float, Float>>) {
    val channels = Integer.bitCount(mask)
    assertEquals(channels, expected.size)
    val mixer = StereoDownmix(channels, mask)
    // Each slot carries a signal in exactly one successive source channel.
    val pcm = ShortArray(channels * channels) { if (it / channels == it % channels) 16_384 else 0 }
    val stereo = FloatArray(channels * 2)
    for ((channel, levels) in expected.withIndex()) {
      mixer.mix(pcm, channel * channels, stereo, channel * 2, 1f)
      assertEquals("left slot $channel", levels.first, stereo[channel * 2], 0.00001f)
      assertEquals("right slot $channel", levels.second, stereo[channel * 2 + 1], 0.00001f)
    }
  }

  private val left = 0.5f to 0f
  private val right = 0f to 0.5f
  private val attenuatedLeft = 0.35355338f to 0f
  private val attenuatedRight = 0f to 0.35355338f
  private val center = 0.35355338f to 0.35355338f
  private val bed = listOf(left, right, center, 0f to 0f, attenuatedLeft, attenuatedRight)
}
