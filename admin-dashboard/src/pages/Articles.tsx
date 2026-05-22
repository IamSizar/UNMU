import Posts from './Posts'
import { useI18n } from '../i18n/I18nContext'

/**
 * Articles — focused view of the unified Posts table, locked to
 * `type=article`. The previous standalone mock UI was replaced with
 * this wrapper so the moderation features (hide/unhide, drill-in,
 * search, sort) all come for free.
 *
 * The dedicated route exists because the admin sidebar lists Articles
 * separately from Videos + Reels and operators expect a one-click jump
 * to "just my articles." Same applies to Videos.jsx.
 */
export default function Articles() {
  const { t } = useI18n()
  return (
    <Posts
      defaultType="article"
      lockType
      title={t('articles.title')}
      subtitle={t('articles.subtitle')}
    />
  )
}
