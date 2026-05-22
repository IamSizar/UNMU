import { useEffect, useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from '../components/Sidebar'
import Header from '../components/Header'
import Toaster from '../components/Toaster'
import { PageTransition } from '../ui/motion'

/**
 * DashboardLayout — top-level shell. Sidebar on the left, sticky
 * Header at the top, scrolling main content area on the right.
 *
 * Redesign notes (May 2026):
 *   - Page background switched from `bg-midnight-500` to `bg-canvas`
 *     (a slightly truer near-black with a 1% blue lift). Cards on the
 *     new pages render at `bg-surface` so depth comes from hairlines,
 *     not a tinted gradient soup.
 *   - Removed the giant blurred cyan/gold blobs that previously washed
 *     every page. They competed with content; the new look earns depth
 *     from typography + hairlines instead of glow halos.
 *   - <Outlet> wrapped in <PageTransition> so every route fades + rises
 *     8px on navigation (200ms ease-out-expo). Respects
 *     prefers-reduced-motion via framer-motion's built-in handling.
 *   - Drawer-open state still locks body scroll (mobile nav).
 */
export default function DashboardLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()

  // Close drawer on route change so navigation feels native on phones.
  useEffect(() => {
    setSidebarOpen(false)
  }, [location.pathname])

  // Lock background scroll while drawer is open on mobile.
  useEffect(() => {
    if (sidebarOpen) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    return () => {
      document.body.style.overflow = ''
    }
  }, [sidebarOpen])

  return (
    <div className="flex h-screen bg-canvas text-fg overflow-hidden">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <div className="flex-1 flex flex-col overflow-hidden min-w-0">
        <Header onOpenSidebar={() => setSidebarOpen(true)} />
        <main className="flex-1 overflow-y-auto overflow-x-hidden">
          {/* Generous outer padding for breathing room — the page itself
              controls its inner max-width. The PageTransition handles
              fade+rise on navigation. */}
          <div className="p-5 sm:p-6 lg:p-8">
            <PageTransition routeKey={location.pathname}>
              <Outlet />
            </PageTransition>
          </div>
        </main>
      </div>
      <Toaster />
    </div>
  )
}
