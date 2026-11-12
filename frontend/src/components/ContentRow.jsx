import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { img, year } from '../api.js'

function PosterCard({ item }) {
  return (
    <Link to={`/contents/${item.media_type}/${item.id}`} className="card card--poster">
      <div className="card__thumb">
        <img src={img(item.poster_path, 'w342')} alt={item.title} loading="lazy" />
      </div>
      <p className="card__title">{item.title}</p>
    </Link>
  )
}

function RankCard({ item, rank }) {
  return (
    <Link to={`/contents/${item.media_type}/${item.id}`} className="card card--rank">
      <div className="card__thumb">
        <img src={img(item.poster_path, 'w342')} alt={item.title} loading="lazy" />
        <span className="card__rank">{rank}</span>
      </div>
      <p className="card__title">{item.title}</p>
    </Link>
  )
}

function LandscapeCard({ item }) {
  const src = img(item.backdrop_path, 'w780') || img(item.poster_path, 'w500')
  return (
    <Link to={`/contents/${item.media_type}/${item.id}`} className="card card--landscape">
      <div className="card__thumb">
        <img src={src} alt={item.title} loading="lazy" />
      </div>
      <p className="card__title">{item.title}</p>
      <p className="card__sub">
        {item.media_type === 'movie' ? '영화' : '시리즈'}
        {item.release_date && ` · ${year(item.release_date)}`}
      </p>
    </Link>
  )
}

export default function ContentRow({ title, layout = 'poster', items }) {
  const trackRef = useRef(null)
  const [edge, setEdge] = useState({ start: true, end: false })

  const update = () => {
    const el = trackRef.current
    if (!el) return
    setEdge({
      start: el.scrollLeft <= 4,
      end: el.scrollLeft + el.clientWidth >= el.scrollWidth - 4,
    })
  }

  useEffect(() => {
    update()
    window.addEventListener('resize', update)
    return () => window.removeEventListener('resize', update)
  }, [items])

  const scroll = (dir) => {
    const el = trackRef.current
    el.scrollBy({ left: dir * el.clientWidth * 0.9, behavior: 'smooth' })
  }

  return (
    <section className={`row row--${layout}`}>
      <h3 className="row__title">{title}</h3>
      <div className="row__body">
        {!edge.start && (
          <button className="row__arrow row__arrow--prev" onClick={() => scroll(-1)} aria-label="이전">
            ‹
          </button>
        )}
        <div className="row__track" ref={trackRef} onScroll={update}>
          {items.map((item, i) =>
            layout === 'rank' ? (
              <RankCard key={`${item.media_type}-${item.id}`} item={item} rank={i + 1} />
            ) : layout === 'landscape' ? (
              <LandscapeCard key={`${item.media_type}-${item.id}`} item={item} />
            ) : (
              <PosterCard key={`${item.media_type}-${item.id}`} item={item} />
            ),
          )}
        </div>
        {!edge.end && (
          <button className="row__arrow row__arrow--next" onClick={() => scroll(1)} aria-label="다음">
            ›
          </button>
        )}
      </div>
    </section>
  )
}

export { PosterCard }
