module HomeHelper
  # Lê os arquivos direto de app/assets/images/admin/clients (qualquer
  # extensão) pra não precisar mexer em código toda vez que um logo de
  # cliente novo for adicionado/removido — só soltar o arquivo na pasta.
  def client_logo_assets
    dir = Rails.root.join('app', 'assets', 'images', 'admin', 'clients')
    Dir.glob(dir.join('*'))
       .select { |path| File.file?(path) }
       .sort
       .map { |path| "admin/clients/#{File.basename(path)}" }
  end

  # Site de cada cliente, pelo nome do arquivo do logo (sem extensão).
  # Logo sem entrada aqui aparece na faixa, só que sem link.
  CLIENT_SITES = {
    'allie'                                        => 'https://alliebrand.com.br/',
    'brysa'                                        => 'https://brysabysa.com.br/',
    'DUNAS-BRANCO'                                 => 'https://dunasdn.com/',
    'email-2024'                                   => 'https://lojaoneway.com/',
    'henrri_negativo'                              => 'https://henrri.com.br/',
    'kace'                                         => 'https://www.kacewear.com.br/',
    'logo'                                         => 'https://www.usezaos.com.br/',
    'Logo_Header_94582ed2-dc65-4f29-8e6a-3e2a2e96ba5b_1' => 'https://minimalclub.com.br/',
    'LOGO_BRANCA'                                  => 'https://fernandafarah.com.br/',
    'logosite1'                                    => 'https://chasebrasil.com/',
    'lyss'                                         => 'https://lyssoficial.com.br/',
    'patoge___798a6e88db039123eb791da15c900bdf'    => 'https://www.loja.patoge.com.br/',
    'royalenfield'                                 => 'https://royalenfield.com.br/',
    'season'                                       => 'https://www.seasonsports.com.br/',
    'TOP_ARARA_5'                                  => 'https://domaniactive.com/',
    'unnamed_6f13f59e-b3a2-4319-89aa-b17039a21da1' => 'https://gethallie.com/',
    'velvy'                                        => 'https://velvycoffee.com.br/',
    'VORR_dog_dourado_texto_preto_transparente'    => 'https://vorr.com.br/',
    'yousports'                                    => 'https://yousports.com.br/'
  }.freeze

  def client_site(logo_path)
    CLIENT_SITES[File.basename(logo_path, '.*')]
  end

  # Lojas criadas pela Mewtda que aparecem na seção "Sua Loja" (03), com
  # os prints de desktop (1600×900) e celular (780×1688) da home de cada uma.
  SITE_CASES = [
    { key: 'fernandafarah', name: 'Fernanda Farah', url: 'https://fernandafarah.com.br/',
      desktop: 'landing/site-desktop.jpg', mobile: 'landing/site-mobile.jpg' },
    { key: 'allie', name: 'Allie', url: 'https://alliebrand.com.br/',
      desktop: 'landing/site-allie-desktop.jpg', mobile: 'landing/site-allie-mobile.jpg' },
    { key: 'patoge', name: 'Patogê', url: 'https://www.loja.patoge.com.br/',
      desktop: 'landing/site-patoge-desktop.jpg', mobile: 'landing/site-patoge-mobile.jpg' },
    { key: 'vorr', name: 'Vörr', url: 'https://vorr.com.br/',
      desktop: 'landing/site-vorr-desktop.jpg', mobile: 'landing/site-vorr-mobile.jpg' }
  ].map { |c| c.merge(host: URI(c[:url]).host.delete_prefix('www.')).freeze }.freeze

  def site_cases
    SITE_CASES
  end

  # Imagens opcionais da landing (ex: print do painel): se o arquivo ainda
  # não foi colocado em app/assets/images, a view usa um fallback em vez de
  # quebrar o asset pipeline.
  def landing_image?(path)
    Rails.root.join('app', 'assets', 'images', path).file?
  end

  # Print real da tela do produto pro painel "Soluções" da home
  # (landing/showcase-<key>.jpg). Sem o arquivo, o painel mostra o mock em HTML.
  def showcase_shot(key)
    path = "landing/showcase-#{key}.jpg"
    path if landing_image?(path)
  end

  # Os 4 produtos da landing, na ordem das seções. Nomes são marca (não
  # traduzem); `anchor` é o id da seção na página. `logo` (opcional)
  # troca o wordmark em CSS pela imagem da marca própria.
  LANDING_PRODUCTS = [
    { key: 'crm',    name: 'MeuCRM',      color: '#0b72e7', icon: 'fa-solid fa-chart-line',              anchor: 'crm',
      logo: 'landing/meu-crm-logo.png' },
    { key: 'trocas', name: 'Pode Trocar', color: '#0b5a36', icon: 'fa-solid fa-arrow-right-arrow-left', anchor: 'trocas',
      logo: 'landing/pode-trocar-logo.png' },
    { key: 'new',    name: 'Sua Loja',    color: '#1a7fdc', icon: 'fa-brands fa-shopify',                anchor: 'sites',
      logo: 'landing/sua-loja-logo.png' },
    { key: 'app',    name: 'App',         color: '#1a7fdc', icon: 'fa-solid fa-mobile-screen',          anchor: 'apps',
      logo: 'landing/app-logo.png' }
  ].freeze

  def landing_products
    LANDING_PRODUCTS
  end

  # Página dedicada de cada produto (vão sendo criadas uma a uma). Produto
  # sem página ainda cai no anchor da seção dele na home — e os botões
  # "Ver a página completa" só aparecem pra quem já tem página. O Pode
  # Trocar tem site próprio, então aponta pra fora.
  PODE_TROCAR_URL = 'https://www.podetrocar.com.br/'.freeze

  def product_page_path(key)
    {
      'crm'    => meu_crm_path,
      'trocas' => PODE_TROCAR_URL,
      'new'    => sua_loja_path,
      'app'    => app_page_path
    }[key.to_s]
  end

  # Vitrine fake do celular (seção 04 da home e página /app). Fotos do
  # Unsplash — pra usar prints reais de lojas de clientes, troque os ids.
  LANDING_APP_SEGMENTS = {
    moda:        { store: 'ATELIÊ',   accent: '#e4572e', banner: '1483985988355-763728e1935b', products: %w[1591047139829-d91aecb6caea 1503342217505-b0a15ec3261c 1542291026-7eec264c27ff 1560343090-f0409e92791a] },
    beleza:      { store: 'glow.co',  accent: '#c2587e', banner: '1596462502278-27bfdc403348', products: %w[1608571423902-eed4a5ad8108 1620916566398-39f1143ab7be 1571781926291-c477ebfd024b 1556228578-8c89e6adf883] },
    eletronicos: { store: 'VOLT',     accent: '#2563eb', banner: '1505740420928-5e560c06d30e', products: %w[1546868871-7041f2a55e12 1583394838336-acd977736f90 1526170375885-4d8ecf77b99f 1523275335684-37898b6baf30] },
    casa:        { store: 'casa.nua', accent: '#0f766e', banner: '1586023492125-27b2c045efd7', products: %w[1555041469-a586c61ea9bc 1567538096630-e0c55bd6374c 1513506003901-1e6a229e2d15 1524758631624-e2822e304c36] }
  }.freeze

  def landing_app_segments
    LANDING_APP_SEGMENTS
  end

  def unsplash_photo(id, width = 360)
    "https://images.unsplash.com/photo-#{id}?w=#{width}&q=70&auto=format&fit=crop"
  end

  def landing_product(key)
    LANDING_PRODUCTS.find { |product| product[:key] == key }
  end
end
