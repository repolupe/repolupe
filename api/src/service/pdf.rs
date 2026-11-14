//! Renders the pages of PDFs as images for the model to look at, when the Markdown converted
//! from them (see [`crate::service::extraction`]) is not enough, e.g. for figures, forms and
//! tables, or to check text recognized with OCR.

use crate::service::image;
use crate::service::llm::Image;
use std::fmt;
use std::time::Duration;
use tokio::sync::Semaphore;

pub(crate) const MIME_TYPE: &str = "application/pdf";

/// A4 and Letter pages get a long edge just below the one [`image::prepare`] scales down to,
/// so they are shown as rendered. Larger pages are scaled down.
const DPI: i32 = 134;
/// Including the wait for a slot.
const TIMEOUT: Duration = Duration::from_secs(30);
/// Pages rendered at once in this process. Each render keeps a core busy and holds the file
/// and the page's pixels in memory.
const MAX_RENDERS: usize = 2;
static RENDER_SLOTS: Semaphore = Semaphore::const_new(MAX_RENDERS);

/// A page of a PDF as the model gets it.
#[derive(Debug)]
pub(crate) struct RenderedPage {
    pub(crate) image: Image,
    /// Pages of the PDF.
    pub(crate) pages: usize,
}

#[derive(Debug, PartialEq)]
pub(crate) enum PageError {
    /// Not a PDF, broken or encrypted.
    Invalid,
    /// The PDF has only `pages` pages.
    Missing {
        pages: usize,
    },
    Failed,
    Timeout,
}

/// For the model.
impl fmt::Display for PageError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid => write!(
                f,
                "The file could not be opened, it may be damaged or encrypted"
            ),
            Self::Missing { pages: 1 } => write!(f, "The file has only 1 page"),
            Self::Missing { pages } => write!(f, "The file has only {pages} pages"),
            Self::Failed => write!(f, "The page could not be rendered"),
            Self::Timeout => write!(f, "Rendering the page took too long"),
        }
    }
}

/// Page `page` (from 1) of the PDF file `content` as an image.
pub(crate) async fn render_page(content: Vec<u8>, page: usize) -> Result<RenderedPage, PageError> {
    let render = async {
        let permit = RENDER_SLOTS
            .acquire()
            .await
            .map_err(|_| PageError::Failed)?;
        // The permit moves into the thread, which keeps running after the timeout, or when the
        // generation is cancelled and this future dropped.
        let task = tokio::task::spawn_blocking(move || {
            let _permit = permit;
            render(&content, page)
        });
        task.await.unwrap_or_else(|e| {
            tracing::error!("Rendering a page of a PDF panicked: {e}");
            Err(PageError::Failed)
        })
    };
    match tokio::time::timeout(TIMEOUT, render).await {
        Ok(result) => result,
        Err(_) => Err(PageError::Timeout),
    }
}

/// See [`render_page`]. Blocking.
fn render(content: &[u8], page: usize) -> Result<RenderedPage, PageError> {
    let session = xberg::pdf::PdfRenderSession::open(content, None).map_err(|e| {
        tracing::info!("Could not open a PDF to render a page: {e}");
        PageError::Invalid
    })?;
    let pages = session.page_count();
    if page == 0 || page > pages {
        return Err(PageError::Missing { pages });
    }
    let png = session
        .render_page_to_png(page - 1, Some(DPI))
        .map_err(|e| {
            tracing::warn!("Could not render page {page} of a PDF: {e}");
            PageError::Failed
        })?;
    let prepared = image::prepare(&png).map_err(|e| {
        tracing::warn!("Could not prepare page {page} of a PDF: {e}");
        PageError::Failed
    })?;
    Ok(RenderedPage {
        image: prepared.image,
        pages,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::llm::ImageFormat;
    use base64::Engine;
    use base64::engine::general_purpose::STANDARD as BASE64;

    const PAGES_PDF: &[u8] = include_bytes!("../../tests/fixtures/pages.pdf");

    #[tokio::test]
    async fn renders_pages() {
        let rendered = render_page(PAGES_PDF.to_vec(), 2).await.unwrap();
        assert_eq!(rendered.pages, 3);
        assert_eq!(rendered.image.format, ImageFormat::Png);
        let image = ::image::load_from_memory(&BASE64.decode(&rendered.image.data).unwrap())
            .unwrap()
            .to_luma8();
        // Letter at 134 dpi
        assert_eq!((image.width(), image.height()), (1139, 1474));
        // Black text on white, in the upper half only
        let dark = |rows: std::ops::Range<u32>| {
            rows.flat_map(|y| (0..image.width()).map(move |x| (x, y)))
                .filter(|&(x, y)| image.get_pixel(x, y).0[0] < 128)
                .count()
        };
        assert!(dark(0..737) > 500);
        assert_eq!(dark(737..1474), 0);
    }

    #[tokio::test]
    async fn rejects_missing_pages_and_other_files() {
        for page in [0, 4] {
            let error = render_page(PAGES_PDF.to_vec(), page).await.unwrap_err();
            assert_eq!(error, PageError::Missing { pages: 3 });
            assert_eq!(error.to_string(), "The file has only 3 pages");
        }
        let error = render_page(b"# Notes\n".to_vec(), 1).await.unwrap_err();
        assert_eq!(error, PageError::Invalid);
    }
}
