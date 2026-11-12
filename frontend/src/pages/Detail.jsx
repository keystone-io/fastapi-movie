import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { api, img, year } from '../api.js'
import useFetch from '../useFetch.js'
import ContentRow from '../components/ContentRow.jsx'
import { ErrorBox, Loading } from '../components/Status.jsx'

function TrailerModal({ videoKey, onClose }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [onClose])

  return (
    <div className="modal" onClick={onClose}>
      <div className="modal__inner" onClick={(e) => e.stopPropagation()}>
        <button className="modal__close" onClick={onClose} aria-label="닫기">
          ✕
        </button>
        <iframe
          src={`https://www.youtube.com/embed/${videoKey}?autoplay=1&rel=0`}
          title="예고편"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowFullScreen
        />
      </div>
    </div>
  )
}

function ageClass(cert) {
  if (!cert) return ''
  if (/^(ALL|All|0)$/i.test(cert)) return 'age--all'
  if (/18|19|청불/.test(cert)) return 'age--19'
  if (/15/.test(cert)) return 'age--15'
  return 'age--12'
}

export default function Detail() {
  const { mediaType, id } = useParams()
  const { data, error, loading } = useFetch(() => api.detail(mediaType, id), [mediaType, id])
  const [trailer, setTrailer] = useState(false)
  const [more, setMore] = useState(false)

  if (loading) return <Loading />
  if (error) return <ErrorBox message={error.message} />

  const d = data
  const meta = [
    year(d.release_date),
    mediaType === 'tv' && d.number_of_seasons ? `시즌 ${d.number_of_seasons}개` : null,
    d.runtime ? `${d.runtime}분` : null,
    ...d.genres.slice(0, 3),
  ].filter(Boolean)

  return (
    <div className="detail">
      <div className="detail__top">
        <div className="detail__bg">
          {d.backdrop_path && <img src={img(d.backdrop_path, 'original')} alt="" />}
        </div>
        <div className="detail__info">
          {d.logo_path ? (
            <img className="detail__logo" src={img(d.logo_path, 'w500')} alt={d.title} />
          ) : (
            <h1 className="detail__title">{d.title}</h1>
          )}

          <div className="detail__meta">
            {d.certification && <span className={`age ${ageClass(d.certification)}`}>{d.certification}</span>}
            {meta.map((m, i) => (
              <span key={i}>{m}</span>
            ))}
            {d.vote_average > 0 && <span className="detail__score">★ {d.vote_average}</span>}
          </div>

          <div className="detail__actions">
            <button className="btn-play" disabled={!d.trailer_key} onClick={() => setTrailer(true)}>
              ▶ {d.trailer_key ? '예고편 보기' : '예고편 없음'}
            </button>
            <button className="btn-icon" aria-label="찜하기">
              ♡
            </button>
          </div>

          {d.tagline && <p className="detail__tagline">{d.tagline}</p>}
          {d.overview && (
            <p className={`detail__overview ${more ? 'is-open' : ''}`} onClick={() => setMore((m) => !m)}>
              {d.overview}
            </p>
          )}

          <dl className="detail__credits">
            {d.cast.length > 0 && (
              <div>
                <dt>출연</dt>
                <dd>{d.cast.slice(0, 5).map((c) => c.name).join(', ')}</dd>
              </div>
            )}
            {d.directors.length > 0 && (
              <div>
                <dt>{mediaType === 'movie' ? '감독' : '크리에이터'}</dt>
                <dd>{d.directors.join(', ')}</dd>
              </div>
            )}
          </dl>
        </div>
        <div className="detail__poster">
          <img src={img(d.poster_path, 'w500')} alt={d.title} />
        </div>
      </div>

      {d.cast.length > 0 && (
        <section className="cast">
          <h3 className="row__title">출연진</h3>
          <ul className="cast__list">
            {d.cast.map((c) => (
              <li key={c.id}>
                <div className="cast__photo">
                  {c.profile_path ? <img src={img(c.profile_path, 'w185')} alt={c.name} loading="lazy" /> : <span>{c.name[0]}</span>}
                </div>
                <strong>{c.name}</strong>
                <small>{c.character}</small>
              </li>
            ))}
          </ul>
        </section>
      )}

      {d.related.length > 0 && (
        <div className="rows rows--detail">
          <ContentRow title="비슷한 콘텐츠" layout="poster" items={d.related} />
        </div>
      )}

      {trailer && <TrailerModal videoKey={d.trailer_key} onClose={() => setTrailer(false)} />}
    </div>
  )
}
