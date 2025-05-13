-- ============================================================================
-- Migration: 007_cms_content.sql
-- Description: Creates Content Management System (CMS) tables: Categories,
--              Content Items, and Translations.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql -- Potentially for author_id relationship
-- ============================================================================

BEGIN;

-- Prefix 'cms_' denotes tables related to the Content Management System module.

-------------------------------------------------------------------------------
-- 1. Content Categories (cms_categories)
-- Description: Defines hierarchical categories for grouping content (e.g., Help -> Payments).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cms_categories (
    category_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_category_id  UUID NULL,          -- For hierarchy (Self-referencing FK defined later)
    slug                VARCHAR(100) NOT NULL UNIQUE, -- URL-friendly identifier (e.g., 'help-payments')
    icon_url            TEXT NULL,          -- Optional URL for a category icon
    sort_order          INTEGER DEFAULT 0 NOT NULL, -- Display order for categories at the same level
    is_active           BOOLEAN DEFAULT TRUE NOT NULL, -- Is the category visible/active?
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.cms_categories
IS '[VoyaGo][CMS] Stores hierarchical categories for organizing content.';
COMMENT ON COLUMN public.cms_categories.parent_category_id
IS 'Reference to the parent category for creating a hierarchy.';
COMMENT ON COLUMN public.cms_categories.slug
IS 'Unique, URL-friendly identifier used in URIs and for referencing the category.';
COMMENT ON COLUMN public.cms_categories.sort_order
IS 'Determines the display order of categories within the same parent.';

-- Indexes for Categories
CREATE INDEX IF NOT EXISTS idx_cms_categories_parent ON public.cms_categories(
    parent_category_id
) WHERE parent_category_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cms_categories_active_order ON public.cms_categories(is_active, sort_order);
-- UNIQUE constraint on slug implicitly creates an index.


-------------------------------------------------------------------------------
-- 2. Category Translations (cms_categories_translations)
-- Description: Stores translations for category names and descriptions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cms_categories_translations (
    category_id     UUID NOT NULL,    -- FK to cms_categories (defined later, ON DELETE CASCADE)
    language_code   CHAR(2) NOT NULL, -- FK to lkp_languages (defined later, ON DELETE CASCADE)
    name            VARCHAR(150) NOT NULL, -- Translated category name
    description     TEXT NULL,        -- Translated category description (optional)
    PRIMARY KEY (category_id, language_code)
);
COMMENT ON TABLE public.cms_categories_translations
IS '[VoyaGo][CMS][I18n] Stores translations for content category names and descriptions.';

-- Index for finding translations by language
CREATE INDEX IF NOT EXISTS idx_cms_categories_translations_lang ON public.cms_categories_translations(language_code);


-------------------------------------------------------------------------------
-- 3. Content Items (cms_content_items)
-- Description: Main record for individual content pieces (articles, FAQs, etc.)
--              and their metadata.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cms_content_items (
    item_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id     UUID NULL,          -- Optional category association (FK to cms_categories, defined later)
    slug            VARCHAR(150) NOT NULL UNIQUE, -- URL-friendly identifier for the content item
    content_type    VARCHAR(20) DEFAULT 'HTML' NOT NULL
    CHECK (content_type IN ('HTML', 'MARKDOWN', 'TEXT', 'JSON')), -- Format of the content body
    status          VARCHAR(20) DEFAULT 'DRAFT' NOT NULL
    CHECK (status IN ('DRAFT', 'PENDING_REVIEW', 'PUBLISHED', 'ARCHIVED')), -- Lifecycle status of the content
    -- User who created/last edited the item (FK to core_user_profiles, defined later)
    author_id       UUID NULL,
    published_at    TIMESTAMPTZ NULL,   -- Timestamp when the content was published
    tags            TEXT[] NULL,        -- Array of tags for categorization and search
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.cms_content_items
IS '[VoyaGo][CMS] Stores metadata for individual content items like articles, FAQs, or announcements.';
COMMENT ON COLUMN public.cms_content_items.slug
IS 'Unique, URL-friendly identifier used for accessing the content item.';
COMMENT ON COLUMN public.cms_content_items.content_type
IS 'Specifies the format of the content stored in the corresponding cms_content_translations.body field.';
COMMENT ON COLUMN public.cms_content_items.status
IS 'Current status in the content lifecycle (Draft, Pending Review, Published, Archived).';
COMMENT ON COLUMN public.cms_content_items.tags
IS 'Array of keywords for tagging content. Example: ARRAY[''payment'', ''credit_card'', ''faq'']';

-- Indexes for Content Items
CREATE INDEX IF NOT EXISTS idx_cms_content_items_category ON public.cms_content_items(
    category_id
) WHERE category_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cms_content_items_status_published ON public.cms_content_items(status, published_at DESC)
WHERE status = 'PUBLISHED'; -- Efficiently find published items, ordered by publish date
COMMENT ON INDEX public.idx_cms_content_items_status_published 
    IS '[VoyaGo][Perf] Optimized index for retrieving published content items.';
CREATE INDEX IF NOT EXISTS idx_cms_content_items_author ON public.cms_content_items(
    author_id
) WHERE author_id IS NOT NULL;
-- GIN index for searching tags efficiently
CREATE INDEX IF NOT EXISTS idx_gin_cms_content_items_tags ON public.cms_content_items USING gin (
    tags
) WHERE tags IS NOT NULL;
COMMENT ON INDEX public.idx_gin_cms_content_items_tags 
    IS '[VoyaGo][Perf] GIN index for efficient searching based on content tags.';


-------------------------------------------------------------------------------
-- 4. Content Translations (cms_content_translations)
-- Description: Stores language-specific title, body, and metadata for content items.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cms_content_translations (
    item_id             UUID NOT NULL,    -- FK to cms_content_items (defined later, ON DELETE CASCADE)
    language_code       CHAR(2) NOT NULL, -- FK to lkp_languages (defined later, ON DELETE CASCADE)
    title               VARCHAR(255) NOT NULL, -- Translated title of the content
    -- Translated body of the content (in format specified by cms_content_items.content_type)
    body                TEXT NOT NULL,
    excerpt             TEXT NULL,        -- Optional translated short summary/excerpt
    meta_title          VARCHAR(255) NULL,-- Translated meta title for SEO
    meta_description    TEXT NULL,        -- Translated meta description for SEO
    updated_at          TIMESTAMPTZ DEFAULT clock_timestamp(), -- Last update time of this specific translation
    PRIMARY KEY (item_id, language_code)
);
COMMENT ON TABLE public.cms_content_translations
IS '[VoyaGo][CMS][I18n] Stores the language-specific content (title, body) and SEO metadata for content items.';
COMMENT ON COLUMN public.cms_content_translations.body
IS 'The actual content body, formatted according to the content_type specified in the parent cms_content_items record.';
COMMENT ON COLUMN public.cms_content_translations.updated_at
IS 'Timestamp indicating the last modification time of this specific translation.';

-- Trigger to update 'updated_at' only when translatable fields change
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cms_content_translations ON public.cms_content_translations;
CREATE TRIGGER trg_set_timestamp_on_cms_content_translations
    BEFORE UPDATE ON public.cms_content_translations
    FOR EACH ROW
    WHEN (
        old.title IS DISTINCT FROM new.title
        OR old.body IS DISTINCT FROM new.body
        OR old.excerpt IS DISTINCT FROM new.excerpt
        OR old.meta_title IS DISTINCT FROM new.meta_title
        OR old.meta_description IS DISTINCT FROM new.meta_description
    )
    EXECUTE FUNCTION public.vg_trigger_set_timestamp();
COMMENT ON TRIGGER trg_set_timestamp_on_cms_content_translations ON public.cms_content_translations
IS 'Updates updated_at only if user-visible translated fields are modified, avoiding unnecessary updates.';

-- Index for finding translations by language
CREATE INDEX IF NOT EXISTS idx_cms_content_translations_lang ON public.cms_content_translations(language_code);

-- Note: Full-Text Search (FTS) indexes can be added later for enhanced search capabilities.
-- Example for Turkish:
-- CREATE INDEX idx_fts_cms_content_translations_tr ON public.cms_content_translations 
    --USING GIN (to_tsvector('turkish', title || ' ' || body || ' ' || coalesce(excerpt,'')));
-- Example for English:
-- CREATE INDEX idx_fts_cms_content_translations_en ON public.cms_content_translations 
    --USING GIN (to_tsvector('english', title || ' ' || body || ' ' || coalesce(excerpt,'')));


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for cms_categories
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cms_categories ON public.cms_categories;
CREATE TRIGGER trg_set_timestamp_on_cms_categories
BEFORE UPDATE ON public.cms_categories
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for cms_content_items
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cms_content_items ON public.cms_content_items;
CREATE TRIGGER trg_set_timestamp_on_cms_content_items
BEFORE UPDATE ON public.cms_content_items
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Note: The specific trigger for cms_content_translations is defined above with a WHEN clause.


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- ============================================================================

-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_categories.parent_category_id to cms_categories.category_id (ON DELETE SET NULL or RESTRICT?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_categories_translations.category_id to cms_categories.category_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_categories_translations.language_code to lkp_languages.code (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_content_items.category_id to cms_categories.category_id (ON DELETE SET NULL) 
    -- Allow content without category
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_content_items.author_id to core_user_profiles.user_id (ON DELETE SET NULL) 
    -- Keep content even if author deleted
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_content_translations.item_id to cms_content_items.item_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from cms_content_translations.language_code to lkp_languages.code (ON DELETE CASCADE)


COMMIT;

-- ============================================================================
-- End of Migration: 007_cms_content.sql
-- ============================================================================
