

PowerShell에서 스크립트 실행 권한을 부여하기 위해, Set-ExecutionPolicy 명령어를 사용할 수 있습니다. 이는 스크립트를 실행하기 전에 필요한 보안 설정을 조정하는 데 사용됩니다. 다음은 main.ps1 파일에 대해 스크립트 실행 권한을 설정하는 방법입니다.

PowerShell을 관리자 권한으로 실행하세요. 이는 스크립트 실행 정책을 변경하기 위해 필요합니다.

실행 정책을 변경하려면 다음 명령어를 입력합니다. 여기서 RemoteSigned, Unrestricted, AllSigned, Restricted 중 하나를 선택할 수 있습니다. 일반적으로 RemoteSigned는 로컬 스크립트는 실행을 허용하지만, 인터넷에서 다운로드한 스크립트는 신뢰할 수 있는 출처에서 서명한 경우에만 실행을 허용하는 중간 수준의 보안 설정입니다.


# Set-ExecutionPolicy RemoteSigned
이 명령은 실행 정책을 'RemoteSigned'로 설정합니다. 필요에 따라 다른 정책을 선택할 수 있습니다.

변경 사항을 적용하려면, Y를 누르거나 Enter 키를 누릅니다.
