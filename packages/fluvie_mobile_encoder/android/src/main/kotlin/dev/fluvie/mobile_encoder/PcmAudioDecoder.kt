package dev.fluvie.mobile_encoder

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.RandomAccessFile
import java.nio.ByteOrder

/** Interleaved 16-bit PCM with sample rate, channel count and a Java positional mask. */
data class DecodedPcm(
  val samples: ShortArray,
  val sampleRate: Int,
  val channels: Int,
  val channelMask: Int = 0,
)

/** Decodes a compressed audio file to interleaved 16-bit PCM via [MediaCodec]. */
object PcmAudioDecoder {
  fun decode(path: String): DecodedPcm {
    val waveSource = isWaveFile(path)
    val extractor = MediaExtractor()
    extractor.setDataSource(path)
    var trackIndex = -1
    var format: MediaFormat? = null
    for (i in 0 until extractor.trackCount) {
      val candidate = extractor.getTrackFormat(i)
      if (candidate.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
        trackIndex = i
        format = candidate
        break
      }
    }
    if (trackIndex < 0 || format == null) {
      extractor.release()
      throw IllegalStateException("no audio track in $path")
    }
    extractor.selectTrack(trackIndex)

    var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val inputChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
    val inputMask = format.channelMask()
    var channels = inputChannels
    var channelMask = decodedChannelMask(inputMask, 0, waveSource, sameChannels = true)
    val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
    codec.configure(format, null, null, 0)
    codec.start()

    val out = ArrayList<Short>()
    val info = MediaCodec.BufferInfo()
    var inputDone = false
    try {
      while (true) {
        if (!inputDone) {
          val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
          if (inIndex >= 0) {
            val buffer = codec.getInputBuffer(inIndex)!!
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) {
              codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              inputDone = true
            } else {
              codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
              extractor.advance()
            }
          }
        }
        val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
        if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
          val output = codec.outputFormat
          sampleRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
          channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
          channelMask = decodedChannelMask(
            inputMask,
            output.channelMask(),
            waveSource,
            sameChannels = channels == inputChannels,
          )
        } else if (outIndex >= 0) {
          val buffer = codec.getOutputBuffer(outIndex)
          if (buffer != null && info.size > 0) {
            val shorts = buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
            while (shorts.hasRemaining()) out.add(shorts.get())
          }
          codec.releaseOutputBuffer(outIndex, false)
          if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
        }
      }
    } finally {
      codec.stop()
      codec.release()
      extractor.release()
    }
    return DecodedPcm(out.toShortArray(), sampleRate, channels, channelMask)
  }

  internal fun decodedChannelMask(
    inputMask: Int,
    outputMask: Int,
    waveSource: Boolean,
    sameChannels: Boolean,
  ): Int {
    // The WAV extractor reads a native positional mask from the container.
    // A decoder that preserves it also preserves that mask's representation.
    val usesInputMask = sameChannels && (outputMask == 0 || outputMask == inputMask)
    val mask = if (usesInputMask) inputMask else outputMask
    return if ((usesInputMask && waveSource) || (mask and 0b11) != 0) mask shl 2 else mask
  }

  private fun isWaveFile(path: String): Boolean = RandomAccessFile(path, "r").use { file ->
    if (file.length() < 12 || file.readInt() != 0x52494646) return@use false // RIFF
    file.seek(8)
    file.readInt() == 0x57415645 // WAVE
  }

  private fun MediaFormat.channelMask(): Int =
    if (containsKey(MediaFormat.KEY_CHANNEL_MASK)) getInteger(MediaFormat.KEY_CHANNEL_MASK) else 0

  private const val TIMEOUT_US = 10_000L
}
