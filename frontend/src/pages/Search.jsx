import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api } from '../api.js'
import { PosterCard } from '../components/ContentRow.jsx'
import { SearchIcon } from '../components/Header.jsx'
import { Loading } from '../components/Status.jsx'

export default function Search() {
  const [params, setParams] = useSearchParams()
  const q = params.get('q') || ''
  const [input, setInput] = useState(q)
  const [state, setState] = useState({ results: [], loading: false, error: null })

  // 입력 디바운스 → URL 쿼리 갱신
  useEffect(() => {
    const t = setTimeout(() => {
      if (input.trim() !== q) setParams(input.trim() ? { q: input.trim() } : {}, { replace: true })
    }, 300)
    return () => clearTimeout(t)
  }, [input, q, setParams])

  useEffect(() => {
    if (!q) {
      setState({ results: [], loading: false, error: null })
      return
    }
    let alive = true
    setState((s) => ({ ...s, loading: true, error: null }))
    api
      .search(q)
      .then((d) => alive && setState({ results: d.results, loading: false, error: null }))
      .catch((e) => alive && setState({ results: [], loading: false, error: e }))
    return () => {
      alive = false
    }
  }, [q])

  return (
    <div className="search">
      <div className="search__box">
        <input
          autoFocus
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="제목, 인물명으로 검색해보세요."
        />
        <SearchIcon size={32} />
      </div>

      {state.loading && <Loading />}
      {state.error && <p className="search__empty">{state.error.message}</p>}
      {!state.loading && q && !state.error && (
        <>
          <h3 className="search__count">
            '{q}' 검색 결과 <strong>{state.results.length}</strong>
          </h3>
          {state.results.length ? (
            <div className="grid">
              {state.results.map((item) => (
                <PosterCard key={`${item.media_type}-${item.id}`} item={item} />
              ))}
            </div>
          ) : (
            <p className="search__empty">검색 결과가 없습니다.</p>
          )}
        </>
      )}
    </div>
  )
}
