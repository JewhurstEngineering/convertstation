# Fixtures

`baseline.mov` is a 2 second, 640×360 H.264 clip with a sine tone. It was generated with the local FFmpeg:

```bash
ffmpeg -f lavfi -i "testsrc=size=640x360:rate=30:duration=2" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest Fixtures/baseline.mov
```

`malformed.mov` is the text `this is not a quicktime file`. Probing it should fail cleanly.

The integration test converts `baseline.mov` to animated WebP, checks the RIFF animation header, and checks that the source bytes do not change.

`silent.mov` is a 1 second, 64×36 H.264 clip with no audio. `tone.wav` is a 1 second 440 Hz tone. `sample.jpg` is a 16×8 red JPEG. They were generated with the local FFmpeg:

```bash
ffmpeg -f lavfi -i "testsrc=size=64x36:rate=30:duration=1" \
  -c:v libx264 -pix_fmt yuv420p -an Fixtures/silent.mov
ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -c:a pcm_s16le Fixtures/tone.wav
ffmpeg -f lavfi -i "color=c=red:size=16x8" -frames:v 1 -update 1 Fixtures/sample.jpg
```
