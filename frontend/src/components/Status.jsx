export function Loading() {
  return (
    <div className="status">
      <div className="spinner" />
    </div>
  )
}

export function ErrorBox({ message }) {
  return (
    <div className="status status--error">
      <p>콘텐츠를 불러오지 못했습니다.</p>
      <small>{message}</small>
    </div>
  )
}
