package dev.fluvie.mobile_encoder

import android.media.AudioFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioMixEncoderTest {
  @Test(timeout = 1_000)
  fun aLoopStartingPastTheSourceEndsWithoutWriting() {
    val pcm = DecodedPcm(ShortArray(9_600) { 8_192 }, 48_000, 1)
    val track = spec(trimStart = 0.5, trimEnd = 1.0, loop = true)

    val mixed = mix(track, pcm)

    assertTrue(mixed.all { it == 0f })
  }

  @Test
  fun loopsAClamped48kHzTrimUntilThePlaybackLimit() {
    val pcm = DecodedPcm(ShortArray(9_600) { if (it < 2_400) 0 else 8_192 }, 48_000, 1)
    val track = spec(trimStart = 0.05, trimEnd = 0.5, delayMs = 500, maxPlayback = 1.0, loop = true)

    val mixed = mix(track, pcm)

    assertEquals(0f, left(mixed, 22_049), 0f)
    assertEquals(0.25f, left(mixed, 22_050), 0f)
    assertEquals(0.25f, left(mixed, 35_280), 0f)
    assertEquals(0.25f, left(mixed, 66_149), 0f)
    assertEquals(0f, left(mixed, 66_150), 0f)
  }

  @Test
  fun a48kHzTrimPlaysOnlyFrom500Through800Milliseconds() {
    val pcm = DecodedPcm(ShortArray(48_000) { if (it < 9_600) 0 else 16_384 }, 48_000, 1)
    val track = spec(trimStart = 0.2, trimEnd = 0.5, delayMs = 500)

    val mixed = mix(track, pcm)

    assertEquals(0f, left(mixed, 22_049), 0f)
    assertEquals(0.5f, left(mixed, 22_050), 0f)
    assertEquals(0.5f, left(mixed, 35_279), 0f)
    assertEquals(0f, left(mixed, 35_280), 0f)
  }

  @Test
  fun routesEvery51PositionWithNativeJavaOrMissingMasks() {
    val track = spec(trimStart = 0.0, trimEnd = 0.2)
    val expected = listOf(
      0.5f to 0f,
      0f to 0.5f,
      0.35355338f to 0.35355338f,
      0f to 0f,
      0.35355338f to 0f,
      0f to 0.35355338f,
    )

    val waveMask = PcmAudioDecoder.decodedChannelMask(0x3f, 0x3f, waveSource = true, sameChannels = true)
    for (mask in listOf(waveMask, AudioFormat.CHANNEL_OUT_5POINT1, 0)) {
      for ((position, levels) in expected.withIndex()) {
        val samples = ShortArray(9_600 * 6) { if (it % 6 == position) 16_384 else 0 }
        val mixed = mix(track, DecodedPcm(samples, 48_000, 6, mask))
        assertEquals("left, mask=$mask, position=$position", levels.first, left(mixed, 100), 0.00001f)
        assertEquals("right, mask=$mask, position=$position", levels.second, mixed[201], 0.00001f)
      }
    }
  }

  @Test
  fun keepsFrontCenterInTheCanonical30Layout() {
    val pcm = DecodedPcm(shortArrayOf(0, 0, 16_384), 48_000, 3)
    val mixed = mix(spec(trimStart = 0.0, trimEnd = 1.0), pcm)

    assertEquals(0.35355338f, mixed[0], 0.00001f)
    assertEquals(0.35355338f, mixed[1], 0.00001f)
  }

  @Test
  fun mixesBackCenterInAnExplicit40Layout() {
    val mask = AudioFormat.CHANNEL_OUT_STEREO or AudioFormat.CHANNEL_OUT_FRONT_CENTER or
      AudioFormat.CHANNEL_OUT_BACK_CENTER
    val pcm = DecodedPcm(shortArrayOf(0, 0, 0, 16_384), 48_000, 4, mask)
    val mixed = mix(spec(trimStart = 0.0, trimEnd = 1.0), pcm)

    assertEquals(0.35355338f, mixed[0], 0.00001f)
    assertEquals(0.35355338f, mixed[1], 0.00001f)
  }

  @Test
  fun readsTheCenterPositionFromTheMask() {
    val mask = AudioFormat.CHANNEL_OUT_FRONT_CENTER or
      AudioFormat.CHANNEL_OUT_BACK_LEFT or AudioFormat.CHANNEL_OUT_BACK_RIGHT
    val pcm = DecodedPcm(shortArrayOf(16_384, 0, 0), 48_000, 3, mask)
    val mixed = mix(spec(trimStart = 0.0, trimEnd = 1.0), pcm)

    assertEquals(0.35355338f, mixed[0], 0.00001f)
    assertEquals(0.35355338f, mixed[1], 0.00001f)
  }

  @Test
  fun routesNativeWaveMasksWithoutFrontLeftOrRight() {
    val track = spec(trimStart = 0.0, trimEnd = 1.0)
    val expected = listOf(
      0.35355338f to 0.35355338f,
      0.35355338f to 0f,
      0f to 0.35355338f,
    )
    for (outputMask in listOf(0, 0x34, 0xd0)) {
      val mask = PcmAudioDecoder.decodedChannelMask(0x34, outputMask, waveSource = true, sameChannels = true)
      for ((position, levels) in expected.withIndex()) {
        val samples = ShortArray(3) { if (it == position) 16_384 else 0 }
        val mixed = mix(track, DecodedPcm(samples, 48_000, 3, mask))
        assertEquals(levels.first, mixed[0], 0.00001f)
        assertEquals(levels.second, mixed[1], 0.00001f)
      }
    }
  }

  @Test
  fun keepsJavaMasksFromOtherSourcesAndDecoderChannelChanges() {
    assertEquals(0x34, PcmAudioDecoder.decodedChannelMask(0, 0x34, waveSource = false, sameChannels = true))
    assertEquals(0x0c, PcmAudioDecoder.decodedChannelMask(0x3f, 0x0c, waveSource = true, sameChannels = false))
    assertEquals(0, PcmAudioDecoder.decodedChannelMask(0x3f, 0, waveSource = true, sameChannels = false))
  }

  @Test
  fun routesFrontOfCenterPositionsIn71WideWave() {
    val mask = PcmAudioDecoder.decodedChannelMask(0xff, 0xff, waveSource = true, sameChannels = true)
    val track = spec(trimStart = 0.0, trimEnd = 1.0)
    for (position in listOf(6, 7)) {
      val samples = ShortArray(8) { if (it == position) 16_384 else 0 }
      val mixed = mix(track, DecodedPcm(samples, 48_000, 8, mask))
      val side = position - 6
      assertEquals(0.35355338f, mixed[side], 0.00001f)
      assertEquals(0f, mixed[1 - side], 0.00001f)
    }
  }

  private fun spec(
    trimStart: Double,
    trimEnd: Double,
    delayMs: Int = 0,
    maxPlayback: Double? = null,
    loop: Boolean = false,
  ) = AudioTrackSpec(
    path = "",
    delayMs = delayMs,
    volume = 1f,
    trimStartSeconds = trimStart,
    trimEndSeconds = trimEnd,
    maxPlaybackSeconds = maxPlayback,
    fadeInSeconds = null,
    fadeOutSeconds = null,
    fadeOutStartSeconds = 0.0,
    loop = loop,
  )

  private fun mix(track: AudioTrackSpec, pcm: DecodedPcm): FloatArray {
    val outputFrames = 88_200
    val output = FloatArray(outputFrames * 2)
    AudioMixEncoder(listOf(track), 1f, 2.0).mixOne(track, pcm, output, outputFrames)
    return output
  }

  private fun left(mix: FloatArray, frame: Int) = mix[frame * 2]
}
