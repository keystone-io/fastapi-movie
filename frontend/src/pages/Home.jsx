import { api } from '../api.js'
import useFetch from '../useFetch.js'
import HeroBanner from '../components/HeroBanner.jsx'
import ContentRow from '../components/ContentRow.jsx'
import { ErrorBox, Loading } from '../components/Status.jsx'

export default function Home() {
  const { data, error, loading } = useFetch(api.home, [])

  if (loading) return <Loading />
  if (error) return <ErrorBox message={error.message} />

  return (
    <>
      <HeroBanner items={data.hero} />
      <div className="rows">
        {data.sections.map((s) => (
          <ContentRow key={s.key} title={s.title} layout={s.layout} items={s.items} />
        ))}
      </div>
    </>
  )
}
