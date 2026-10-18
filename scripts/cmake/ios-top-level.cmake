# Incluído no topo do projeto do chiaki-ng pelo scripts/build_chiaki_ios.sh (CMAKE_PROJECT_TOP_LEVEL_INCLUDES).
# O lib/CMakeLists.txt chama pkg_search_module(LIBEVENT ...) sem ter carregado o módulo PkgConfig no mesmo
# escopo quando json-c e miniupnpc vêm das opções *_EXTERNAL_PROJECT (no Mac o json-c do Homebrew faz esse
# carregamento antes), e a chamada falha. Carregar o módulo aqui evita mexer no submódulo.
find_package(PkgConfig REQUIRED)
