/// The Markdown converted from a document, or why that failed.
pub(crate) enum DocumentExtraction {
    Completed {
        markdown: String,
        /// Whether pages were recognized with OCR, so the text may contain errors.
        ocr: bool,
    },
    /// Shown to the model.
    Failed { error: String },
}

/// The Markdown of a completed extraction.
pub(crate) struct ExtractedMarkdown {
    pub(crate) blob_oid: String,
    pub(crate) markdown: String,
    /// Whether pages were recognized with OCR, so the text may contain errors.
    pub(crate) ocr: bool,
}
