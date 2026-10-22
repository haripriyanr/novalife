"""DICOM Image Loader & ROI Mask Extractor.

Handles DICOM file IO using pydicom, synthetic medical phantom generation for testing,
and clinical Region-of-Interest (ROI) segmentation via Otsu thresholding.
"""
from __future__ import annotations

import pathlib
import numpy as np
import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, SecondaryCaptureImageStorage, generate_uid

N = 512


def create_synthetic_dicom(output_path: str | pathlib.Path, seed: int = 7010) -> Dataset:
    """Generate a 512x512 synthetic medical DICOM image (phantom X-ray) with ROI."""
    output_path = pathlib.Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    np.random.seed(seed)
    # Background gradient
    x = np.linspace(-1, 1, N)
    y = np.linspace(-1, 1, N)
    xx, yy = np.meshgrid(x, y)
    r = np.sqrt(xx**2 + yy**2)
    
    # Anatomical phantom (ellipse ROI representing lung/chest)
    roi_region = (r < 0.75) & ((xx / 0.7)**2 + (yy / 0.8)**2 < 0.75)
    img = np.zeros((N, N), dtype=np.float64)
    img[roi_region] = 180 + 40 * np.cos(3 * xx[roi_region]) * np.sin(3 * yy[roi_region])
    # Add noise outside and inside
    img += np.random.normal(0, 5, (N, N))
    img = np.clip(img, 0, 255).astype(np.uint8)

    file_meta = FileMetaDataset()
    file_meta.MediaStorageSOPClassUID = SecondaryCaptureImageStorage
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

    ds = FileDataset(str(output_path), {}, file_meta=file_meta, preamble=b"\0" * 128)
    ds.PatientName = "ABHA^PATIENT^1001"
    ds.PatientID = "ABHA-91-8820-4102"
    ds.Modality = "CR"
    ds.Rows = N
    ds.Columns = N
    ds.BitsAllocated = 8
    ds.BitsStored = 8
    ds.HighBit = 7
    ds.PixelRepresentation = 0
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.PixelData = img.tobytes()

    ds.save_as(str(output_path), write_like_original=False)
    return ds


def load_dicom_or_create(path: str | pathlib.Path) -> tuple[np.ndarray, np.ndarray, Dataset]:
    """Load DICOM image or create synthetic DICOM if missing.
    
    Returns:
        image: 512x512 uint8 numpy array
        roi_mask: 512x512 uint8 array (1 = ROI / clinical area, 0 = non-ROI embedding background)
        ds: pydicom Dataset
    """
    path = pathlib.Path(path)
    if not path.exists():
        ds = create_synthetic_dicom(path)
    else:
        ds = pydicom.dcmread(str(path))

    img = ds.pixel_array.astype(np.float64)
    if img.max() > 255:
        img = (img / img.max() * 255.0)
    img = np.clip(img, 0, 255).astype(np.uint8)

    # Compute ROI mask via thresholding
    # ROI = anatomical content (high variance or brightness > threshold)
    threshold = np.mean(img) + 0.2 * np.std(img)
    roi_mask = (img > threshold).astype(np.uint8)

    return img, roi_mask, ds
