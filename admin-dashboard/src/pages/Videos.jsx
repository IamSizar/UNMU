import Posts from './Posts'
import { useI18n } from '../i18n/I18nContext'

/**
 * Videos — focused view of the unified Posts table, defaulting to
 * video posts. Unlike Articles we leave the type pills enabled so an
 * operator can flip between long-form video and short-form reels
 * without leaving the page — the two formats live on the same row
 * shape in the backend and most moderation actions span both.
 */
export default function Videos() {
  const { t } = useI18n()
  return (
    <Posts
      defaultType="video"
      title={t('videos.title')}
      subtitle={t('videos.subtitle')}
    />
  )
}
