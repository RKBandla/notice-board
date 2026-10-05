import { useEffect, useState } from 'react'

// API Gateway base URL is injected at build time:
//   VITE_API_URL=https://<api-id>.execute-api.us-east-1.amazonaws.com npm run build
const API_BASE = (import.meta.env.VITE_API_URL || '').replace(/\/+$/, '')
const API_URL = `${API_BASE}/notices`

export default function App() {
  const [notices, setNotices] = useState([])
  const [title, setTitle] = useState('')
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const fetchNotices = async () => {
    try {
      setError('')
      const res = await fetch(API_URL)
      if (!res.ok) throw new Error(`Server returned ${res.status}`)
      const data = await res.json()
      setNotices(Array.isArray(data) ? data.reverse() : [])
    } catch (e) {
      setError(`Could not load notices (${e.message}). Check VITE_API_URL.`)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchNotices() }, [])

  const createNotice = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, content }),
      })
      if (!res.ok) throw new Error(`Server returned ${res.status}`)
      setTitle('')
      setContent('')
      await fetchNotices()
    } catch (e) {
      setError(`Could not post notice (${e.message}).`)
    } finally {
      setSaving(false)
    }
  }

  const deleteNotice = async (id) => {
    try {
      const res = await fetch(`${API_URL}/${id}`, { method: 'DELETE' })
      if (!res.ok) throw new Error(`Server returned ${res.status}`)
      setNotices((list) => list.filter((n) => n._id !== id))
    } catch (e) {
      setError(`Could not delete notice (${e.message}).`)
    }
  }

  return (
    <div className="page">
      <header className="header">
        <h1>📌 Notice Board</h1>
        <p>Post announcements for everyone to see. Auto-deployed by GitHub Actions.</p>
      </header>

      <form className="card form" onSubmit={createNotice}>
        <input
          placeholder="Title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          required
        />
        <textarea
          placeholder="Content"
          rows={3}
          value={content}
          onChange={(e) => setContent(e.target.value)}
          required
        />
        <button type="submit" disabled={saving}>
          {saving ? 'Posting…' : 'Add Notice'}
        </button>
      </form>

      {error && <div className="error">{error}</div>}

      <h2>All Notices</h2>
      {loading && <p className="muted">Loading notices…</p>}
      {!loading && !error && notices.length === 0 && (
        <p className="muted">No notices yet. Post the first one above.</p>
      )}

      <div className="list">
        {notices.map((n) => (
          <article key={n._id} className="card notice">
            <div>
              <h3>{n.title}</h3>
              <p>{n.content}</p>
            </div>
            <button className="delete" onClick={() => deleteNotice(n._id)}>
              Delete
            </button>
          </article>
        ))}
      </div>

      <footer className="footer">React · API Gateway · Lambda · MongoDB · S3 + CloudFront</footer>
    </div>
  )
}
