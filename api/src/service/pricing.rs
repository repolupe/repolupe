//! The cost of an answer, from the tokens it used and the prices of its model.

use crate::service::llm::Usage;
use rust_decimal::Decimal;

const TOKENS_PER_PRICE: u64 = 1_000_000;

/// The prices of a model, per million tokens. Only known if the currency and the input and output
/// prices are set.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Pricing {
    /// ISO 4217 code, e.g. `USD`.
    pub currency: String,
    /// Input not read from or written to the cache.
    pub input: Decimal,
    pub output: Decimal,
    /// `None` charges `input`.
    pub cache_read: Option<Decimal>,
    /// `None` charges `input`.
    pub cache_write: Option<Decimal>,
}

impl Pricing {
    /// `None` if the currency, input or output price is not set.
    pub(crate) fn new(
        currency: Option<String>,
        input: Option<Decimal>,
        output: Option<Decimal>,
        cache_read: Option<Decimal>,
        cache_write: Option<Decimal>,
    ) -> Option<Self> {
        Some(Pricing {
            currency: currency?,
            input: input?,
            output: output?,
            cache_read,
            cache_write,
        })
    }

    /// In [`Self::currency`], unrounded.
    pub(crate) fn cost(&self, usage: &Usage) -> Decimal {
        let total = Decimal::from(usage.input_tokens) * self.input
            + Decimal::from(usage.output_tokens) * self.output
            + Decimal::from(usage.cache_read_input_tokens) * self.cache_read.unwrap_or(self.input)
            + Decimal::from(usage.cache_creation_input_tokens)
                * self.cache_write.unwrap_or(self.input);
        (total / Decimal::from(TOKENS_PER_PRICE)).normalize()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    fn price(value: &str) -> Decimal {
        Decimal::from_str(value).unwrap()
    }

    fn usage(input: u64, output: u64, cache_read: u64, cache_write: u64) -> Usage {
        Usage {
            input_tokens: input,
            output_tokens: output,
            cache_read_input_tokens: cache_read,
            cache_creation_input_tokens: cache_write,
        }
    }

    #[test]
    fn needs_input_and_output_price() {
        let currency = || Some("USD".to_string());
        assert!(Pricing::new(currency(), Some(price("3")), None, None, None).is_none());
        assert!(Pricing::new(currency(), None, Some(price("15")), None, None).is_none());
        assert!(
            Pricing::new(currency(), Some(price("3")), Some(price("15")), None, None).is_some()
        );
        assert!(Pricing::new(None, Some(price("3")), Some(price("15")), None, None).is_none());
    }

    #[test]
    fn charges_each_kind_of_token() {
        let pricing = Pricing::new(
            Some("USD".to_string()),
            Some(price("3")),
            Some(price("15")),
            Some(price("0.30")),
            Some(price("3.75")),
        )
        .unwrap();
        // 0.003 + 0.015 + 0.0003 + 0.00375
        assert_eq!(
            pricing.cost(&usage(1000, 1000, 1000, 1000)),
            price("0.02205")
        );
    }

    #[test]
    fn charges_input_price_for_cache_without_price() {
        let pricing = Pricing::new(
            Some("EUR".to_string()),
            Some(price("2")),
            Some(price("8")),
            None,
            None,
        )
        .unwrap();
        assert_eq!(pricing.cost(&usage(0, 0, 500_000, 500_000)), price("2"));
    }

    #[test]
    fn costs_nothing_without_tokens() {
        let pricing = Pricing::new(
            Some("USD".to_string()),
            Some(price("3")),
            Some(price("15")),
            None,
            None,
        )
        .unwrap();
        assert_eq!(pricing.cost(&Usage::default()), Decimal::ZERO);
    }
}
