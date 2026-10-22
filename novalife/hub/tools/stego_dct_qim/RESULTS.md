# Transform-Domain Steganography Experiment

See `metrics.json` for exact output.

- none: PSNR 50.78 dB, global SSIM 0.999912, BER 0.000000, payload_ok=True
- JPEG quality=70: PSNR 44.70 dB, global SSIM 0.999644, BER 0.000000, payload_ok=True
- AWGN sigma=2: PSNR 41.24 dB, global SSIM 0.999243, BER 0.000000, payload_ok=True

Fixed-step control: PSNR 51.99 dB, global SSIM 0.999933.

The keyed schedule is a security aid, not encryption; encrypt/authenticate the payload before ECC in deployment.
