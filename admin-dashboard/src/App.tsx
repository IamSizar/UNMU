import { Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './auth/AuthContext'
import DashboardLayout from './layouts/DashboardLayout'
import Dashboard from './pages/Dashboard'
import Users from './pages/Users'
import Experts from './pages/Experts'
import Applications from './pages/Applications'
import Articles from './pages/Articles'
import Videos from './pages/Videos'
import Stocks from './pages/Stocks'
import Subscriptions from './pages/Subscriptions'
import Promos from './pages/Promos'
import Ads from './pages/Ads'
import Notifications from './pages/Notifications'
import Payouts from './pages/Payouts'
import Reports from './pages/Reports'
import Settings from './pages/Settings'
import Login from './pages/Login'
import AuditLog from './pages/AuditLog'
import Uploads from './pages/Uploads'
import Diagnostics from './pages/Diagnostics'
import Posts from './pages/Posts'
import PostDetail from './pages/PostDetail'
import UserDetail from './pages/UserDetail'
import Communities from './pages/Communities'
import CommunityDetail from './pages/CommunityDetail'
import CommunityProposals from './pages/CommunityProposals'
import CommunityProposalDetail from './pages/CommunityProposalDetail'
import Polls from './pages/Polls'
import PollDetail from './pages/PollDetail'
import SubscriptionDetail from './pages/SubscriptionDetail'
import ApplicationDetail from './pages/ApplicationDetail'
import AuditLogDetail from './pages/AuditLogDetail'
import CommunitySubscriptions from './pages/CommunitySubscriptions'
import CommunitySubscriptionDetail from './pages/CommunitySubscriptionDetail'
import Support from './pages/Support'
// Network — live platform map (force-directed graph of every
// expert/user/community relationship + pending events feed).
import Network from './pages/Network'
import type { ReactElement } from 'react'

function RequireAdmin({ children }: { children: ReactElement }) {
  const { user } = useAuth()
  if (!user) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <RequireAdmin>
              <DashboardLayout />
            </RequireAdmin>
          }
        >
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          {/* Live platform-relationship map. Sits in the sidebar
              directly under Overview. */}
          <Route path="network" element={<Network />} />
          <Route path="users" element={<Users />} />
          <Route path="users/:id" element={<UserDetail />} />
          <Route path="experts" element={<Experts />} />
          <Route path="applications" element={<Applications />} />
          {/* Unified moderation page (articles + videos + reels). The
              old /articles + /videos routes still resolve to their mock
              pages for now — keeping them lets us roll back if needed. */}
          <Route path="posts" element={<Posts />} />
          <Route path="posts/:id" element={<PostDetail />} />
          <Route path="communities" element={<Communities />} />
          <Route path="communities/:id" element={<CommunityDetail />} />
          <Route path="community-proposals" element={<CommunityProposals />} />
          {/* Step-22 — drill-in detail pages for actionable rows
              (subscriptions / applications / proposals / audit / polls).
              Each row in the corresponding list page navigates here for
              full context + Approve/Reject controls in a proper form. */}
          <Route
            path="community-proposals/:id"
            element={<CommunityProposalDetail />}
          />
          <Route path="subscriptions/:id" element={<SubscriptionDetail />} />
          <Route path="applications/:id" element={<ApplicationDetail />} />
          <Route path="audit-log/:id" element={<AuditLogDetail />} />
          {/* Step-21 (mig 0021, item 5.21) — admin chat-polls panel. */}
          <Route path="polls" element={<Polls />} />
          <Route path="polls/:id" element={<PollDetail />} />
          {/* Step-23 (mig 0022) — paid community memberships queue. */}
          <Route
            path="community-subscriptions"
            element={<CommunitySubscriptions />}
          />
          <Route
            path="community-subscriptions/:id"
            element={<CommunitySubscriptionDetail />}
          />
          {/* Mig 0029 — built-in user ↔ admin chat. Same component
              renders the inbox at /support and the thread detail at
              /support/:id (it switches on the :id param). */}
          <Route path="support" element={<Support />} />
          <Route path="support/:id" element={<Support />} />
          <Route path="articles" element={<Articles />} />
          <Route path="videos" element={<Videos />} />
          <Route path="stocks" element={<Stocks />} />
          <Route path="subscriptions" element={<Subscriptions />} />
          <Route path="promos" element={<Promos />} />
          <Route path="ads" element={<Ads />} />
          <Route path="notifications" element={<Notifications />} />
          <Route path="reports" element={<Reports />} />
          <Route path="payouts" element={<Payouts />} />
          <Route path="audit-log" element={<AuditLog />} />
          <Route path="uploads" element={<Uploads />} />
          <Route path="diagnostics" element={<Diagnostics />} />
          <Route path="settings" element={<Settings />} />
        </Route>
      </Routes>
    </AuthProvider>
  )
}
