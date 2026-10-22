# Keyed Adaptive DCT-QIM Reference

This is the first reproducible image-level steganography experiment for NovaLife HUB.
It is a software reference model for the future Zynq-7010 PL accelerator, not yet an
FPGA implementation.

## Run

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
curl -L 'https://upload.wikimedia.org/wikipedia/en/7/7d/Lenna_%28test_image%29.png' -o cover.png
python run_experiment.py --cover cover.png --out .
```

The method uses an 8x8 DCT, HMAC-SHA256 keyed block and coefficient selection,
adaptive QIM, and temporary Hamming(7,4) coding. The embedding rule is:

`c' = 2 Delta round((c - b Delta) / (2 Delta)) + b Delta`

with `Delta = 16 + 0.15 sigma_local`. The key selects locations; it is not a
substitute for authenticated encryption. Hamming must be replaced by a tested
RS/BCH decoder before production claims are made.
