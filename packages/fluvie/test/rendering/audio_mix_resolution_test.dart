import 'package:flutter_test/flutter_test.dart';
import 'package:fluvie/fluvie.dart';
import 'package:fluvie/rendering.dart';

void main() {
  group('resolveAudioMix', () {
    test('starts overlapping clip audio with the image and uses the source trim', () {
      final video = Video(
        transition: const Transition.crossFade(Time.frames(12)),
        scenes: [
          const Scene(duration: Time.frames(30)),
          Scene(
            duration: const Time.frames(30),
            children: [Clip.asset('dialogue.mp4', trim: 48.frames.to(72.frames))],
          ),
        ],
      );

      final mix = resolveAudioMix(
        video: video,
        fps: 30,
        totalFrames: video.totalFrames,
        clipMetadataFor: (_) => (fps: 24, frameCount: 96, width: 16, height: 16, hasAudio: true),
      );

      expect(video.sceneStartFrames[1], 18);
      expect(mix.tracks.single.delayMs, 600);
      expect(mix.tracks.single.trimStartSeconds, 2);
      expect(mix.tracks.single.trimEndSeconds, 3);
    });

    test('scene music and SFX use the resolved scene clock', () {
      final video = Video(
        transition: const Transition.crossFade(Time.frames(12)),
        audio: const [Audio.music('global.wav')],
        scenes: [
          const Scene(duration: Time.frames(30)),
          Scene(
            duration: const Time.frames(30),
            audio: [
              const Audio.music('scene.wav'),
              Audio.sfx('pop.wav', at: Trigger.at(0.5.relative)),
            ],
          ),
        ],
      );

      final mix = resolveAudioMix(video: video, fps: 30, totalFrames: video.totalFrames);

      expect(mix.tracks.map((track) => track.delayMs), [0, 600, 1100]);
      expect(mix.tracks[0].maxPlaybackSeconds, isNull);
      expect(mix.tracks[1].maxPlaybackSeconds, closeTo(1, 1e-10));
      expect(mix.tracks[2].maxPlaybackSeconds, closeTo(0.5, 1e-10));
    });

    test('clip audio starts and ends with its animate window', () {
      final video = Video(
        scenes: [
          Scene(
            duration: const Time.frames(30),
            children: [
              Clip.asset('dialogue.mp4').animate(const [], window: 15.frames.to(24.frames)),
            ],
          ),
        ],
      );

      final track = resolveAudioMix(video: video, fps: 30, totalFrames: 30).tracks.single;

      expect(track.delayMs, 500);
      expect(track.trimStartSeconds, 0);
      expect(track.trimEndSeconds, 0.3);
    });

    test('resolves a wall-clock clip trim without metadata and caps it to the scene', () {
      final video = Video(
        scenes: [
          Scene(
            duration: const Time.frames(30),
            children: [Clip.asset('dialogue.mp4', trim: 2.seconds.to(5.seconds))],
          ),
        ],
      );

      final track = resolveAudioMix(video: video, fps: 30).tracks.single;

      expect(track.trimStartSeconds, 2);
      expect(track.trimEndSeconds, 3);
    });

    test('a video with no audio resolves to an empty mix', () {
      final video = Video(
        size: VideoSize.square,
        scenes: [Scene(duration: 2.seconds)],
      );
      final mix = resolveAudioMix(video: video, fps: 30, totalFrames: 60);
      expect(mix.isEmpty, isTrue);
      expect(mix.tracks, isEmpty);
      expect(mix.masterVolume, 1);
    });

    test('a music bed resolves to a track with its source and gain', () {
      final video = Video(
        size: VideoSize.square,
        audio: const [Audio.music('audio/song.mp3', volume: 0.8, fadeIn: Time.frames(30))],
        scenes: [Scene(duration: 2.seconds)],
      );

      final mix = resolveAudioMix(video: video, fps: 30, totalFrames: 180);

      expect(mix.tracks, hasLength(1));
      final track = mix.tracks.single;
      expect(track.source, 'audio/song.mp3');
      expect(track.volume, 0.8);
      expect(track.fadeInSeconds, 1.0);
      expect(track.delayMs, 0);
      expect(track.loop, isFalse);
    });

    test('matches the FFmpeg mix timing: trim, fade-out anchor, and sfx delay', () {
      final video = Video(
        size: VideoSize.square,
        audio: [
          Audio.music('audio/song.mp3', trim: 0.seconds.to(2.seconds), fadeOut: 15.frames),
          Audio.sfx('audio/ping.wav', at: Trigger.at(1.seconds)),
        ],
        scenes: [Scene(duration: 6.seconds)],
      );

      final mix = resolveAudioMix(video: video, fps: 30, totalFrames: 180);

      final music = mix.tracks[0];
      expect(music.source, 'audio/song.mp3');
      expect(music.trimStartSeconds, 0.0);
      expect(music.trimEndSeconds, 2.0);
      // A 0.5 s fade-out ends at the 2 s trim, so it begins at 1.5 s.
      expect(music.fadeOutStartSeconds, 1.5);

      final sfx = mix.tracks[1];
      expect(sfx.source, 'audio/ping.wav');
      expect(sfx.delayMs, 1000); // Trigger.at(1.seconds) at 30 fps
    });
  });
}
