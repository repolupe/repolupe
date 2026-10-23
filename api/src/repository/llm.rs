use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::llm::LlmApiFormat;
use crate::model::llm_model::{AvailableModel, LlmModel, ModelConnection, ModelPrices};
use crate::model::llm_provider::LlmProvider;
use crate::repository::repository::StoredToken;
use crate::repository::{begin_write, violates_unique};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use sqlx::types::Text;
use uuid::Uuid;

pub(crate) struct NewLlmProvider<'a> {
    pub id: Uuid,
    pub name: &'a str,
    pub api_format: LlmApiFormat,
    pub base_url: &'a str,
    pub api_key: Option<StoredToken>,
    pub currency: Option<&'a str>,
}

pub(crate) struct LlmProviderChanges<'a> {
    pub name: &'a str,
    pub api_format: LlmApiFormat,
    pub base_url: &'a str,
    /// `None` keeps the key, `Some(None)` clears it, `Some(Some(_))` replaces it.
    pub api_key: Option<Option<StoredToken>>,
    pub currency: Option<&'a str>,
}

/// Creates or replaces a model.
pub(crate) struct LlmModelFields<'a> {
    pub api_name: &'a str,
    pub display_name: Option<&'a str>,
    pub max_output_tokens: Option<i32>,
    pub prices: ModelPrices,
}

pub(crate) async fn list_providers(db: &DatabasePool) -> Result<Vec<LlmProvider>, AppError> {
    let providers = sqlx::query_as!(
        LlmProvider,
        r#"SELECT id AS "id: Uuid", name, api_format AS "api_format: LlmApiFormat", base_url,
                  api_key_encrypted, api_key_hint, currency, created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM llm_providers
           ORDER BY lower(name), id"#,
    )
    .fetch_all(db)
    .await?;
    Ok(providers)
}

pub(crate) async fn get_provider(
    db: &DatabasePool,
    id: Uuid,
) -> Result<Option<LlmProvider>, AppError> {
    let provider = sqlx::query_as!(
        LlmProvider,
        r#"SELECT id AS "id: Uuid", name, api_format AS "api_format: LlmApiFormat", base_url,
                  api_key_encrypted, api_key_hint, currency, created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM llm_providers
           WHERE id = $1"#,
        id,
    )
    .fetch_optional(db)
    .await?;
    Ok(provider)
}

pub(crate) async fn create_provider(
    db: &DatabasePool,
    new: NewLlmProvider<'_>,
) -> Result<LlmProvider, AppError> {
    let (api_key_encrypted, api_key_hint) = split_key(new.api_key);
    let now = Utc::now();
    let provider = sqlx::query_as!(
        LlmProvider,
        r#"INSERT INTO llm_providers (id, name, api_format, base_url, api_key_encrypted, api_key_hint,
                                      currency, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
           RETURNING id AS "id: Uuid", name, api_format AS "api_format: LlmApiFormat", base_url,
                     api_key_encrypted, api_key_hint, currency, created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        new.id,
        new.name,
        new.api_format,
        new.base_url,
        api_key_encrypted,
        api_key_hint,
        new.currency,
        now,
    )
    .fetch_one(db)
    .await
    .map_err(map_provider_name_conflict)?;
    Ok(provider)
}

/// Applies `changes` if the row still has `expected_base_url`, and clears the currency only if
/// none of its models has prices. Returns `None` if the provider does not exist, its URL changed
/// in the meantime, or the currency cannot be cleared.
pub(crate) async fn update_provider(
    db: &DatabasePool,
    id: Uuid,
    expected_base_url: &str,
    changes: LlmProviderChanges<'_>,
) -> Result<Option<LlmProvider>, AppError> {
    let replace_key = changes.api_key.is_some();
    let (api_key_encrypted, api_key_hint) = split_key(changes.api_key.flatten());
    let now = Utc::now();
    let provider = sqlx::query_as!(
        LlmProvider,
        r#"UPDATE llm_providers
           SET name              = $3,
               api_format        = $4,
               base_url          = $5,
               api_key_encrypted = CASE WHEN $6 THEN $7 ELSE api_key_encrypted END,
               api_key_hint      = CASE WHEN $6 THEN $8 ELSE api_key_hint END,
               currency          = $9,
               updated_at        = $10
           WHERE id = $1 AND base_url = $2
             AND ($9 IS NOT NULL
               OR NOT EXISTS (SELECT 1 FROM llm_models WHERE provider_id = $1 AND input_price IS NOT NULL))
           RETURNING id AS "id: Uuid", name, api_format AS "api_format: LlmApiFormat", base_url,
                     api_key_encrypted, api_key_hint, currency, created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        expected_base_url,
        changes.name,
        changes.api_format,
        changes.base_url,
        replace_key,
        api_key_encrypted,
        api_key_hint,
        changes.currency,
        now,
    )
    .fetch_optional(db)
    .await
    .map_err(map_provider_name_conflict)?;
    Ok(provider)
}

/// Also deletes its models. Users who chose one of them fall back to the default model.
pub(crate) async fn delete_provider(db: &DatabasePool, id: Uuid) -> Result<(), AppError> {
    sqlx::query!("DELETE FROM llm_providers WHERE id = $1", id)
        .execute(db)
        .await?;
    Ok(())
}

pub(crate) async fn list_models(db: &DatabasePool) -> Result<Vec<LlmModel>, AppError> {
    let models = sqlx::query_as!(
        LlmModel,
        r#"SELECT id AS "id: Uuid", provider_id AS "provider_id: Uuid", api_name, display_name, max_output_tokens,
                  input_price AS "input_price: Text<Decimal>", output_price AS "output_price: Text<Decimal>",
                  cache_read_price AS "cache_read_price: Text<Decimal>", cache_write_price AS "cache_write_price: Text<Decimal>",
                  is_default, created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>"
           FROM llm_models
           ORDER BY lower(COALESCE(display_name, api_name)), id"#,
    )
    .fetch_all(db)
    .await?;
    Ok(models)
}

/// The first model becomes the default model. Returns `None` if the provider does not exist, or
/// the model has prices and the provider no currency.
pub(crate) async fn create_model(
    db: &DatabasePool,
    provider_id: Uuid,
    fields: LlmModelFields<'_>,
) -> Result<Option<LlmModel>, AppError> {
    let id = Uuid::now_v7();
    let [
        input_price,
        output_price,
        cache_read_price,
        cache_write_price,
    ] = fields.prices.to_db();
    let now = Utc::now();
    let model = sqlx::query_as!(
        LlmModel,
        r#"INSERT INTO llm_models (id, provider_id, api_name, display_name, max_output_tokens, input_price, output_price,
                                   cache_read_price, cache_write_price, is_default, created_at, updated_at)
           SELECT $1, p.id, $3, $4, $5, $6, $7, $8, $9,
                  NOT EXISTS (SELECT 1 FROM llm_models WHERE is_default), $10, $10
           FROM llm_providers p
           WHERE p.id = $2 AND ($6 IS NULL OR p.currency IS NOT NULL)
           RETURNING id AS "id: Uuid", provider_id AS "provider_id: Uuid", api_name, display_name, max_output_tokens,
                     input_price AS "input_price: Text<Decimal>", output_price AS "output_price: Text<Decimal>",
                     cache_read_price AS "cache_read_price: Text<Decimal>", cache_write_price AS "cache_write_price: Text<Decimal>",
                     is_default, created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        provider_id,
        fields.api_name,
        fields.display_name,
        fields.max_output_tokens,
        input_price,
        output_price,
        cache_read_price,
        cache_write_price,
        now,
    )
    .fetch_optional(db)
    .await
    .map_err(map_model_conflict)?;
    Ok(model)
}

/// Returns `None` if the model does not exist, or it has prices and its provider no currency.
pub(crate) async fn update_model(
    db: &DatabasePool,
    id: Uuid,
    fields: LlmModelFields<'_>,
) -> Result<Option<LlmModel>, AppError> {
    let [
        input_price,
        output_price,
        cache_read_price,
        cache_write_price,
    ] = fields.prices.to_db();
    let now = Utc::now();
    let model = sqlx::query_as!(
        LlmModel,
        r#"UPDATE llm_models
           SET api_name          = $2,
               display_name      = $3,
               max_output_tokens = $4,
               input_price       = $5,
               output_price      = $6,
               cache_read_price  = $7,
               cache_write_price = $8,
               updated_at        = $9
           WHERE id = $1
             AND ($5 IS NULL
               OR (SELECT currency FROM llm_providers p WHERE p.id = provider_id) IS NOT NULL)
           RETURNING id AS "id: Uuid", provider_id AS "provider_id: Uuid", api_name, display_name, max_output_tokens,
                     input_price AS "input_price: Text<Decimal>", output_price AS "output_price: Text<Decimal>",
                     cache_read_price AS "cache_read_price: Text<Decimal>", cache_write_price AS "cache_write_price: Text<Decimal>",
                     is_default, created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        fields.api_name,
        fields.display_name,
        fields.max_output_tokens,
        input_price,
        output_price,
        cache_read_price,
        cache_write_price,
        now,
    )
    .fetch_optional(db)
    .await
    .map_err(map_model_conflict)?;
    Ok(model)
}

pub(crate) async fn model_exists(db: &DatabasePool, id: Uuid) -> Result<bool, AppError> {
    let exists = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM llm_models WHERE id = $1) AS "exists!: bool""#,
        id,
    )
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// Users who chose the model fall back to the default model.
pub(crate) async fn delete_model(db: &DatabasePool, id: Uuid) -> Result<(), AppError> {
    sqlx::query!("DELETE FROM llm_models WHERE id = $1", id)
        .execute(db)
        .await?;
    Ok(())
}

/// Makes `id` the default model and clears the flag of all others. Returns `false` if the model
/// does not exist, in which case nothing changes.
pub(crate) async fn set_default_model(db: &DatabasePool, id: Uuid) -> Result<bool, AppError> {
    let mut tx = begin_write(db).await?;
    // Cleared first, since the unique index is checked row by row
    sqlx::query!(
        "UPDATE llm_models SET is_default = false WHERE is_default AND id <> $1",
        id,
    )
    .execute(&mut *tx)
    .await?;
    let result = sqlx::query!("UPDATE llm_models SET is_default = true WHERE id = $1", id)
        .execute(&mut *tx)
        .await
        .map_err(map_model_conflict)?;
    if result.rows_affected() == 0 {
        return Ok(false);
    }
    tx.commit().await?;
    Ok(true)
}

/// All models, as users see them.
pub(crate) async fn list_available_models(
    db: &DatabasePool,
) -> Result<Vec<AvailableModel>, AppError> {
    let models = sqlx::query_as!(
        AvailableModel,
        r#"SELECT m.id AS "id: Uuid", COALESCE(m.display_name, m.api_name) AS "display_name!: String",
                  p.id AS "provider_id: Uuid", p.name AS provider_name, m.is_default
           FROM llm_models m
           JOIN llm_providers p ON p.id = m.provider_id
           ORDER BY lower(p.name), p.id, lower(COALESCE(m.display_name, m.api_name)), m.id"#,
    )
    .fetch_all(db)
    .await?;
    Ok(models)
}

/// The first of these that exists: `model_id` (chosen for the chat), the model the
/// user chose, the default model. `None` if none exists.
pub(crate) async fn get_model_connection(
    db: &DatabasePool,
    user_id: Uuid,
    model_id: Option<Uuid>,
) -> Result<Option<ModelConnection>, AppError> {
    let connection = sqlx::query_as!(
        ModelConnection,
        r#"SELECT m.id AS "model_id: Uuid", p.id AS "provider_id: Uuid", p.api_format AS "api_format: LlmApiFormat",
                  p.base_url, p.api_key_encrypted, m.api_name AS model, m.max_output_tokens, p.currency,
                  m.input_price AS "input_price: Text<Decimal>", m.output_price AS "output_price: Text<Decimal>",
                  m.cache_read_price AS "cache_read_price: Text<Decimal>",
                  m.cache_write_price AS "cache_write_price: Text<Decimal>"
           FROM llm_models m
           JOIN llm_providers p ON p.id = m.provider_id
           WHERE m.id = COALESCE((SELECT id FROM llm_models WHERE id = $2),
                                 (SELECT default_model_id FROM users WHERE id = $1),
                                 (SELECT id FROM llm_models WHERE is_default))"#,
        user_id,
        model_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(connection)
}

impl ModelPrices {
    fn to_db(self) -> [Option<Text<Decimal>>; 4] {
        [self.input, self.output, self.cache_read, self.cache_write].map(|price| price.map(Text))
    }
}

fn split_key(key: Option<StoredToken>) -> (Option<Vec<u8>>, Option<String>) {
    match key {
        Some(key) => (Some(key.encrypted), key.hint),
        None => (None, None),
    }
}

fn map_provider_name_conflict(e: sqlx::Error) -> AppError {
    if violates_unique(&e, "index 'idx_llm_providers_name'") {
        AppError::Conflict(
            ErrorCode::NameTaken,
            "A provider with this name already exists".to_string(),
        )
    } else {
        AppError::Database(e)
    }
}

fn map_model_conflict(e: sqlx::Error) -> AppError {
    // idx_llm_models_provider_api_name
    if violates_unique(&e, "llm_models.provider_id, llm_models.api_name") {
        AppError::Conflict(
            ErrorCode::NameTaken,
            "The provider already has a model with this API name".to_string(),
        )
    } else if violates_unique(&e, "index 'idx_llm_models_display_name'") {
        AppError::Conflict(
            ErrorCode::NameTaken,
            "A model with this display name already exists, or with this API name if it has none"
                .to_string(),
        )
    } else if violates_unique(&e, "llm_models.is_default") {
        // idx_llm_models_default
        AppError::Conflict(
            ErrorCode::Conflict,
            "The default model was changed by another request, please retry".to_string(),
        )
    } else {
        AppError::Database(e)
    }
}
