import { useEffect, useState } from 'react'
import { Link, NavLink } from 'react-router-dom'

export function SearchIcon({ size = 28 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" strokeWidth="2" />
      <path d="M15.5 15.5L20 20" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

export default function Header() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 10)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <header className={`header ${scrolled ? 'is-scrolled' : ''}`}>
      <div className="header__left">
        <Link to="/" className="logo" aria-label="홈으로">
          MOVING
        </Link>
        <nav className="gnb">
          <NavLink to="/tv">TV프로그램</NavLink>
          <NavLink to="/movie">영화</NavLink>
        </nav>
      </div>
      <div className="header__right">
        <Link to="/search" className="header__icon" aria-label="검색">
          <SearchIcon />
        </Link>
        <button className="profile" aria-label="프로필">
          <span />
        </button>
      </div>
    </header>
  )
}
