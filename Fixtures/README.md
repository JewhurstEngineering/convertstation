# Fixtures

`baseline.mov` is a 2 second, 640×360 H.264 clip with a sine tone. It was generated with the local FFmpeg:

```bash
ffmpeg -f lavfi -i "testsrc=size=640x360:rate=30:duration=2" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest Fixtures/baseline.mov
```

`malformed.mov` is the text `this is not a quicktime file`. Probing it should fail cleanly.

The integration test converts `baseline.mov` to animated WebP, checks the RIFF animation header, and checks that the source bytes do not change.
