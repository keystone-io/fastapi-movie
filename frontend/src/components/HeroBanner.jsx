import { Link } from 'react-router-dom'
import { Swiper, SwiperSlide } from 'swiper/react'
import { Autoplay, Navigation, Pagination } from 'swiper/modules'
import 'swiper/css'
import 'swiper/css/navigation'
import 'swiper/css/pagination'
import { img } from '../api.js'

export default function HeroBanner({ items }) {
  if (!items.length) return null

  return (
    <section className="hero">
      <Swiper
        modules={[Autoplay, Navigation, Pagination]}
        slidesPerView="auto"
        centeredSlides
        spaceBetween={10}
        loop={items.length > 2}
        speed={600}
        autoplay={{ delay: 5000, disableOnInteraction: false, pauseOnMouseEnter: true }}
        navigation
        pagination={{ clickable: true }}
      >
        {items.map((item) => (
          <SwiperSlide key={`${item.media_type}-${item.id}`} className="hero__slide">
            <Link to={`/contents/${item.media_type}/${item.id}`} className="hero__link">
              <img className="hero__bg" src={img(item.backdrop_path, 'original')} alt="" />
              <div className="hero__shade" />
              <div className="hero__content">
                {item.logo_path ? (
                  <img className="hero__logo" src={img(item.logo_path, 'w500')} alt={item.title} />
                ) : (
                  <h2 className="hero__title">{item.title}</h2>
                )}
                <p className="hero__overview">{item.overview}</p>
              </div>
            </Link>
          </SwiperSlide>
        ))}
      </Swiper>
    </section>
  )
}
