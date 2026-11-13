//! Prepares the images the model looks at, which it gets from the tools that read files: in a
//! format both API formats take, and scaled down so that they cost few tokens and stay below
//! the limits of the APIs.

use crate::service::llm::{Image, ImageFormat};
use crate::util::path::has_extension;
use ::image::codecs::jpeg::JpegEncoder;
use ::image::imageops::FilterType;
use ::image::{DynamicImage, ImageDecoder, ImageReader};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use std::fmt;
use std::io::Cursor;

/// Of the files [`prepare`] reads.
const EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "gif", "webp"];
/// Larger files are not shown.
pub(crate) const MAX_IMAGE_BYTES: u64 = 10 * 1024 * 1024;
/// Images with a longer edge are scaled down to it, which keeps the request small and their
/// tokens few (about width × height / 750 for Anthropic's models).
const MAX_EDGE: u32 = 1568;
/// Larger files are encoded again even if their edges are short enough. Anthropic takes up to
/// 5 MB per image, and base64 adds a third.
const MAX_UNCHANGED_BYTES: usize = 3 * 1024 * 1024;
/// Images with more pixels are not decoded, which would take hundreds of megabytes.
const MAX_PIXELS: u64 = 64_000_000;
const JPEG_QUALITY: u8 = 85;

/// Whether the file at `path` is an image the model can look at, by its extension.
pub(crate) fn is_image(path: &str) -> bool {
    has_extension(path, EXTENSIONS)
}

/// The MIME type of the image file `content`, by its signature, or `None` if it is not in one
/// of the formats of [`is_image`].
pub(crate) fn mime_type(content: &[u8]) -> Option<&'static str> {
    match ::image::guess_format(content).ok()? {
        ::image::ImageFormat::Png => Some("image/png"),
        ::image::ImageFormat::Jpeg => Some("image/jpeg"),
        ::image::ImageFormat::Gif => Some("image/gif"),
        ::image::ImageFormat::WebP => Some("image/webp"),
        _ => None,
    }
}

/// An image file as the model gets it.
#[derive(Debug)]
pub(crate) struct Prepared {
    pub(crate) image: Image,
    /// What the file is, for the model, e.g. `PNG image, 536 × 536 px`, with the size of `image`
    /// if it is not the file itself.
    pub(crate) description: String,
}

#[derive(Debug, PartialEq)]
pub(crate) enum ImageError {
    /// Not an image in one of the formats, or broken.
    Invalid,
    TooManyPixels {
        width: u32,
        height: u32,
    },
}

/// For the model.
impl fmt::Display for ImageError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid => write!(f, "It is not a valid PNG, JPEG, GIF or WebP image"),
            Self::TooManyPixels { width, height } => {
                write!(f, "It is too large ({width} × {height} px)")
            }
        }
    }
}

/// The image file `content` for the model: as it is if it is small, otherwise scaled down and
/// encoded again, as a PNG if it has transparency and as a JPEG if not. Blocking.
pub(crate) fn prepare(content: &[u8]) -> Result<Prepared, ImageError> {
    // Recognizes the format by the content, not by the name of the file
    let reader = ImageReader::new(Cursor::new(content))
        .with_guessed_format()
        .map_err(invalid)?;
    let (format, format_name) = match reader.format() {
        Some(::image::ImageFormat::Png) => (ImageFormat::Png, "PNG"),
        Some(::image::ImageFormat::Jpeg) => (ImageFormat::Jpeg, "JPEG"),
        Some(::image::ImageFormat::Gif) => (ImageFormat::Gif, "GIF"),
        Some(::image::ImageFormat::WebP) => (ImageFormat::Webp, "WebP"),
        _ => return Err(ImageError::Invalid),
    };
    // Reads only the header
    let decoder = reader.into_decoder().map_err(invalid)?;
    let (width, height) = decoder.dimensions();
    if u64::from(width) * u64::from(height) > MAX_PIXELS {
        return Err(ImageError::TooManyPixels { width, height });
    }
    let description = format!("{format_name} image, {width} × {height} px");
    if width.max(height) <= MAX_EDGE && content.len() <= MAX_UNCHANGED_BYTES {
        let data = BASE64.encode(content);
        return Ok(Prepared {
            image: Image { format, data },
            description,
        });
    }

    let shown = decode_scaled(decoder)?;
    let (width, height) = (shown.width(), shown.height());
    Ok(Prepared {
        image: encode(&shown)?,
        description: format!("{description}, shown at {width} × {height} px"),
    })
}

/// The image of `decoder`, upright and with edges of at most [`MAX_EDGE`].
fn decode_scaled(mut decoder: impl ImageDecoder) -> Result<DynamicImage, ImageError> {
    // Lost when encoding again, e.g. of a photo taken upright
    let orientation = decoder.orientation().map_err(invalid)?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(invalid)?;
    image.apply_orientation(orientation);
    if image.width().max(image.height()) > MAX_EDGE {
        // Keeps the aspect ratio
        image = image.resize(MAX_EDGE, MAX_EDGE, FilterType::CatmullRom);
    }
    Ok(image)
}

/// `image` as a PNG if it has transparency and as a JPEG if not.
fn encode(image: &DynamicImage) -> Result<Image, ImageError> {
    let mut encoded = Vec::new();
    let format = if image.color().has_alpha() {
        image
            .write_to(&mut Cursor::new(&mut encoded), ::image::ImageFormat::Png)
            .map_err(invalid)?;
        ImageFormat::Png
    } else {
        image
            .to_rgb8()
            .write_with_encoder(JpegEncoder::new_with_quality(&mut encoded, JPEG_QUALITY))
            .map_err(invalid)?;
        ImageFormat::Jpeg
    };
    Ok(Image {
        format,
        data: BASE64.encode(encoded),
    })
}

fn invalid<E>(_: E) -> ImageError {
    ImageError::Invalid
}

/// A PNG file of `width` × `height` pixels, with transparency if `alpha`.
#[cfg(test)]
pub(crate) fn test_png(width: u32, height: u32, alpha: bool) -> Vec<u8> {
    let image = if alpha {
        DynamicImage::new_rgba8(width, height)
    } else {
        DynamicImage::new_rgb8(width, height)
    };
    let mut encoded = Vec::new();
    image
        .write_to(&mut Cursor::new(&mut encoded), ::image::ImageFormat::Png)
        .unwrap();
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode(image: &Image) -> DynamicImage {
        ::image::load_from_memory(&BASE64.decode(&image.data).unwrap()).unwrap()
    }

    #[test]
    fn recognizes_images_by_extension() {
        assert!(is_image("docs/logo.png"));
        assert!(is_image("Photo.JPG"));
        assert!(is_image("scan.webp"));
        assert!(!is_image("drawing.svg"));
        assert!(!is_image("photo.heic"));
        assert!(!is_image("png"));
    }

    #[test]
    fn recognizes_formats_by_signature() {
        assert_eq!(mime_type(&test_png(2, 2, false)), Some("image/png"));
        assert_eq!(mime_type(b"\xff\xd8\xff\xe0"), Some("image/jpeg"));
        assert_eq!(mime_type(b"GIF89a"), Some("image/gif"));
        assert_eq!(mime_type(b"RIFF\0\0\0\0WEBPVP8 "), Some("image/webp"));
        // An image, but not one the browsers and the app show
        assert_eq!(mime_type(b"BM\0\0\0\0"), None);
        assert_eq!(
            mime_type(b"<svg xmlns=\"http://www.w3.org/2000/svg\"/>"),
            None
        );
        assert_eq!(mime_type(b""), None);
    }

    #[test]
    fn keeps_small_images_as_they_are() {
        let png = test_png(536, 268, false);
        let prepared = prepare(&png).unwrap();
        assert_eq!(prepared.image.format, ImageFormat::Png);
        assert_eq!(prepared.image.data, BASE64.encode(&png));
        assert_eq!(prepared.description, "PNG image, 536 × 268 px");
    }

    #[test]
    fn scales_large_images_down() {
        let prepared = prepare(&test_png(3136, 1568, false)).unwrap();
        assert_eq!(prepared.image.format, ImageFormat::Jpeg);
        let shown = decode(&prepared.image);
        assert_eq!((shown.width(), shown.height()), (1568, 784));
        assert_eq!(
            prepared.description,
            "PNG image, 3136 × 1568 px, shown at 1568 × 784 px"
        );

        // Transparency needs a PNG
        let prepared = prepare(&test_png(1000, 2000, true)).unwrap();
        assert_eq!(prepared.image.format, ImageFormat::Png);
        let shown = decode(&prepared.image);
        assert_eq!((shown.width(), shown.height()), (784, 1568));
        assert!(shown.color().has_alpha());
    }

    #[test]
    fn rejects_other_files() {
        // Only the signature of a PNG
        assert_eq!(
            prepare(b"\x89PNG\r\n\x1a\n\0\0\0").unwrap_err(),
            ImageError::Invalid
        );
        assert_eq!(prepare(b"# Notes\n").unwrap_err(), ImageError::Invalid);
        assert_eq!(
            ImageError::Invalid.to_string(),
            "It is not a valid PNG, JPEG, GIF or WebP image"
        );
    }
}
