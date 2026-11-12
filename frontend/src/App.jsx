import { useEffect } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import Header from './components/Header.jsx'
import Footer from './components/Footer.jsx'
import Home from './pages/Home.jsx'
import Browse from './pages/Browse.jsx'
import Detail from './pages/Detail.jsx'
import Search from './pages/Search.jsx'

export default function App() {
  const { pathname } = useLocation()
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [pathname])

  return (
    <>
      <Header />
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/tv" element={<Browse mediaType="tv" key="tv" />} />
          <Route path="/movie" element={<Browse mediaType="movie" key="movie" />} />
          <Route path="/contents/:mediaType/:id" element={<Detail />} />
          <Route path="/search" element={<Search />} />
        </Routes>
      </main>
      <Footer />
    </>
  )
}
