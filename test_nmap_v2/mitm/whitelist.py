NOISE_HOSTS = ["tivan.naver.com", "nmap.place.naver.com", ".veta.naver.com"]
NOISE_EXTS = [".mvt", ".png", ".jpg", ".jpeg", ".woff", ".ttf", ".svg", ".js", ".css", ".sdf"]

def should_process(host: str, path: str) -> bool:
    host_lower = host.lower()
    path_lower = path.lower()

    # 1. 초입 필터: .naver.com 또는 .navercorp.com 이 포함되지 않은 도메인은 모두 통과 (처리 대상에서 제외)
    if ".naver.com" not in host_lower and ".navercorp.com" not in host_lower:
        return False

    # 2. 확장자 필터: 지정된 확장자가 경로에 포함되면 제외
    if any(ext in path_lower for ext in NOISE_EXTS):
        return False

    # 3. 도메인(노이즈) 필터: 특정 노이즈 도메인이 포함되면 제외
    if any(nh in host_lower for nh in NOISE_HOSTS):
        return False

    return True
