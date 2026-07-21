# App OSM - Rotas Acessíveis (TCC) 🧑‍🦽👩‍🦯

Este repositório contém a implementação completa do aplicativo de rotas focado em acessibilidade para o IF Goiano, desenvolvido como Projeto de Conclusão de Curso (TCC). O projeto utiliza dados livres do **OpenStreetMap (OSM)**, **GraphHopper** para roteamento customizado local e **Flutter** para o aplicativo mobile.

## 🏗️ Arquitetura do Projeto

O projeto está dividido em duas partes principais dentro deste repositório:
1. `/backend`: Contém os dados geográficos do campus, modelos de roteamento de acessibilidade e o servidor Java GraphHopper.
2. `/app`: O código-fonte do aplicativo móvel multiplataforma construído em Flutter.

---

## ⚙️ 1. Como rodar o Backend (GraphHopper)

O aplicativo precisa que o servidor de rotas (GraphHopper) esteja rodando localmente na sua máquina para funcionar, já que ele é o responsável por ler o mapa `.osm` e aplicar as penalidades para cadeirantes e deficientes visuais.

### Pré-requisitos
- Java JRE 17 ou superior (o projeto usa o embutido `jre17\jdk-17.0.11+9-jre\bin\java.exe`).

### Passo a passo
1. Abra um terminal ou prompt de comando.
2. Navegue até a pasta `backend`:
   ```bash
   cd "C:\Users\Richa\Documents\App OSM\backend"
   ```
3. Execute o GraphHopper com o arquivo de configuração e o mapa do campus:
   ```bash
   # Para Windows, usando o JRE especificado
   & "jre17\jdk-17.0.11+9-jre\bin\java.exe" -jar graphhopper.jar server config.yml
   ```
4. Aguarde a mensagem `started`. O servidor agora estará ouvindo na porta **8989** (`http://localhost:8989`).
> O GraphHopper irá gerar o cache na pasta `graph-cache`. Não a delete a menos que atualize o arquivo `campus.osm`.

---

## 📱 2. Como rodar o Aplicativo Mobile (Flutter)

O aplicativo é o cliente final que exibe o mapa, busca as salas e dita as instruções por áudio.

### Pré-requisitos
- Flutter SDK instalado.
- Android Studio / SDK para emuladores Android ou celular físico via cabo USB.

### Importante sobre o IP Local
Se você for testar o aplicativo em um **Emulador Android**, o código já está configurado para acessar `10.0.2.2`, que é como o emulador enxerga o seu computador. 
Se for testar em um **celular físico (via USB ou Wi-Fi)**, é obrigatório trocar o IP no arquivo `app/lib/services/routing_service.dart`:
```dart
// Altere de '10.0.2.2' para o IP local do seu computador na rede Wi-Fi (Ex: 192.168.1.15)
final String _baseUrl = 'http://192.168.1.15:8989/route';
```

### Passo a passo
1. Abra um terminal.
2. Navegue até a pasta `app`:
   ```bash
   cd "C:\Users\Richa\Documents\App OSM\app"
   ```
3. Baixe as dependências do projeto:
   ```bash
   flutter pub get
   ```
4. Com um emulador aberto ou celular conectado, rode:
   ```bash
   flutter run
   ```

---

## 🌟 Principais Funcionalidades Implementadas
- **5 Perfis de Mobilidade:** Carro, Moto, Pedestre, Cadeirante e Deficiente Visual.
- **Roteamento Interno:** Navegação por dentro de blocos se mapeados como `highway=corridor`.
- **Busca Offline de Locais:** 933 locais do IF Goiano estão armazenados em `app/assets/pois.json` e podem ser buscados sem internet na lupa do aplicativo.
- **Navegação com Áudio TTS:** Acompanhamento via GPS e sintetizador de voz nativo dando instruções de viradas para auxiliar deficientes visuais.
- **Mapa Customizado:** Integração com OpenStreetMap renderizando tiles fluidas.

## 🔄 Como atualizar o mapa do Campus
Se você fizer modificações de ruas ou acessibilidade lá no site do OpenStreetMap, para trazer para o app:
1. Apague a pasta `backend/graph-cache`.
2. Baixe o novo mapa usando a Overpass API via Powershell (ajustando a área se necessário):
   ```powershell
   Invoke-WebRequest -Uri "https://overpass-api.de/api/map?bbox=-50.925,-17.825,-50.885,-17.780" -OutFile "backend\campus.osm"
   ```
3. Na pasta `app`, rode o script Python para recriar os POIs buscáveis:
   ```bash
   python extract_pois.py
   ```
4. Reinicie o GraphHopper.
