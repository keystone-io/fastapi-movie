const BASE = '/api'

async function get(path, params) {
  const qs = params ? '?' + new URLSearchParams(params) : ''
  const res = await fetch(BASE + path + qs)
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(body.detail || `요청 실패 (${res.status})`)
  }
  return res.json()
}

export const api = {
  home: () => get('/home'),
  browse: (mediaType) => get(`/browse/${mediaType}`),
  detail: (mediaType, id) => get(`/detail/${mediaType}/${id}`),
  search: (q) => get('/search', { q }),
}

export const img = (path, size = 'w500') =>
  path ? `https://image.tmdb.org/t/p/${size}${path}` : null

export const year = (date) => (date ? date.slice(0, 4) : '')
