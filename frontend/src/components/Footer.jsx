export default function Footer() {
  return (
    <footer className="footer">
      <ul className="footer__links">
        <li>고객문의</li>
        <li>공지사항</li>
        <li>이용약관</li>
        <li><strong>개인정보처리방침</strong></li>
        <li>청소년보호정책</li>
        <li>회사안내</li>
      </ul>
      <p className="footer__info">
        본 서비스는 학습용 프로젝트이며 콘텐츠 정보와 이미지는 TMDB API에서 제공됩니다.
        <br />
        This product uses the TMDB API but is not endorsed or certified by TMDB.
      </p>
      <p className="footer__copy">© MOVING. All rights reserved.</p>
    </footer>
  )
}
