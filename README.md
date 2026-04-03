# YOLOv8 Multi-Modal Fusion (RGB + Sp) with AlignWarp + CMGA

## Project Layout

- `build_model.py`: quick sanity check (parse model YAML + initialize network)
- `models/`: model architecture YAMLs (AlignWarp + CMGA)
- `mm_modules.py`: custom modules (ChannelSelect / AlignWarp / CMGA_Guidance / SSENhance / IN)
- `patch_ultralytics.py`: runtime patch for Ultralytics (custom module parsing + multi-channel input)
- `main.py`: training entry (CLI args; `--data` or `DATA_YAML`)
- `val.py`: evaluation entry (prints Precision/Recall/mAP50/mAP50-95/FPS)
- `requirements.txt`: minimal dependencies

## Installation

Run inside `github_upload`:

```bash
pip install -r requirements.txt
```

## Quick Sanity Check (Build Model)

```bash
python build_model.py
```

If you see `BUILD_OK`, the model YAML and custom modules can be parsed and instantiated successfully.

## Data Setup (Multi-Channel Input)

Ultralytics data loading typically produces 3-channel images. This project supports 4/6-channel input via a runtime patch and supports two dataset organizations:

1) Single-file stacked: each image under `images/train|val` is already a 4/6-channel image (e.g., RGB + 1-channel heatmap; or RGB + 3-channel pseudo-color IR).

2) RGB + SP split folders: `images/train|val` contains RGB; provide an extra SP/IR image directory. Add this to your dataset YAML:

```yaml
mm_sp_dir: path/to/sp_images  # filenames must match RGB (same stem)
```

## Training

Prepare a standard Ultralytics dataset YAML (train/val paths, names, etc.), then run:

Windows:

```bash
python main.py
```

Linux/macOS:

```bash
python main.py
```

For RGB + SP split folders, set `mm_sp_dir` inside your dataset YAML as shown above.

Common overrides (recommended, no source edits):

```bash
python main.py --data path/to/your_dataset.yaml --model models/spatial_spectral_enhance.yaml --epochs 100 --batch 2 --imgsz 1280 --ch 4 --name scratch_ch4_align_cmga
```

You can also keep using `DATA_YAML` if you prefer environment variables:

```bash
set DATA_YAML=D:\path\to\your_dataset.yaml
python main.py
```

## Reproducibility Notes

- To reproduce the same metrics, you must evaluate on the same validation split (the same `data.yaml`, or the same `--val-images` directory).

## License

This repository is licensed under GNU AGPLv3. See the root [LICENSE](../LICENSE). This project is built on top of Ultralytics YOLOv8; please follow the upstream license and attribution requirements:
- https://github.com/ultralytics/ultralytics
