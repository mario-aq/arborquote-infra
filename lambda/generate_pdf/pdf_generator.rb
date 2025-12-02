require 'prawn'

# PDF Generator for ArborQuote
# Generates professional quote PDFs in English and Spanish
module PdfGenerator
  # Brand colors from ArborQuote design system
  BRAND_GREEN = '2E7D32'
  LIGHT_GRAY = '666666'
  BORDER_GRAY = 'CCCCCC'

  class << self
    # Generate PDF in English
    def generate_pdf_en(quote, user = nil, company = nil)
      generate_pdf(quote, user, company, :en)
    end

    # Generate PDF in Spanish
    def generate_pdf_es(quote, user = nil, company = nil)
      generate_pdf(quote, user, company, :es)
    end

    private

    # Main PDF generation method
    def generate_pdf(quote, user, company, locale)
      pdf = Prawn::Document.new(page_size: 'LETTER', margin: 40)
      
      # Get localized strings
      strings = locale == :es ? spanish_strings : english_strings
      
      # Header with logo and quote info
      render_header(pdf, quote, strings)
      
      # Provider and Customer information (two columns)
      pdf.move_down 30
      render_info_columns(pdf, quote, user, company, strings)
      
      # Items section
      pdf.move_down 30
      render_section_title(pdf, strings[:requested_work])
      render_items(pdf, quote, strings)
      
      # Total
      pdf.move_down 20
      render_total(pdf, quote, strings)
      
      # Footer
      render_footer(pdf, strings)
      
      # Return PDF as string
      pdf.render
    end

    # Render header with logo and quote metadata
    def render_header(pdf, quote, strings)
      pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
        # Logo and title on left
        pdf.float do
          # Get logo path (relative to this file)
          logo_path = File.join(File.dirname(__FILE__), 'assets', 'logo.png')
          
          if File.exist?(logo_path)
            # Calculate logo height to match text (28pt text ≈ 40px height)
            logo_height = 40
            pdf.image logo_path, height: logo_height, position: :left
            
            # Position text to the right of logo
            pdf.move_up logo_height
            pdf.indent(logo_height + 10) do
              pdf.text 'ArborQuote', size: 28, style: :bold, color: BRAND_GREEN
            end
          else
            # Fallback if logo not found
            pdf.text 'ArborQuote', size: 28, style: :bold, color: BRAND_GREEN
          end
        end
        
        # Quote info on right
        pdf.bounding_box([pdf.bounds.width - 200, pdf.cursor], width: 200) do
          pdf.text "#{strings[:quote]}: #{quote['quoteId']}", 
                   size: 10, align: :right, color: LIGHT_GRAY
          pdf.text "#{strings[:date]}: #{format_date(quote['createdAt'])}", 
                   size: 10, align: :right, color: LIGHT_GRAY
        end
      end
      
      pdf.move_down 10
    end

    # Render section title with green underline
    def render_section_title(pdf, title)
      pdf.text title, size: 18, style: :bold, color: BRAND_GREEN
      pdf.stroke_color BORDER_GRAY
      pdf.stroke_horizontal_rule
      pdf.move_down 10
    end

    # Render provider and customer information in two columns
    def render_info_columns(pdf, quote, user, company, strings)
      # Calculate column width (with some spacing between)
      column_width = (pdf.bounds.width - 20) / 2
      
      # Save the starting Y position for both columns
      start_y = pdf.cursor
      
      # Provider column (left)
      pdf.bounding_box([0, start_y], width: column_width) do
        render_section_title(pdf, strings[:provider_info])
        
        if company
          # Show company information
          pdf.text company['companyName'], size: 12, style: :bold if company['companyName']
          pdf.move_down 3
          
          # Show provider name if user exists
          if user && user['name']
            pdf.text "#{strings[:provider]}: #{user['name']}", size: 11
            pdf.move_down 3
          end
          
          pdf.text "#{strings[:phone]}: #{company['phone']}", size: 11 if company['phone']
          pdf.move_down 3 if company['phone']
          
          pdf.text "#{strings[:email]}: #{company['email']}", size: 11 if company['email']
          pdf.move_down 3 if company['email']
          
          pdf.text "#{strings[:website]}: #{company['website']}", size: 11 if company['website']
          pdf.move_down 3 if company['website']
          
          pdf.text "#{strings[:address]}: #{company['address']}", size: 11 if company['address']
        elsif user
          # Show user information (independent provider)
          pdf.text user['name'], size: 12, style: :bold if user['name']
          pdf.move_down 3 if user['name']
          
          pdf.text "#{strings[:phone]}: #{user['phone']}", size: 11 if user['phone']
          pdf.move_down 3 if user['phone']
          
          pdf.text "#{strings[:email]}: #{user['email']}", size: 11 if user['email']
          pdf.move_down 3 if user['email']
          
          pdf.text "#{strings[:address]}: #{user['address']}", size: 11 if user['address']
        else
          # No provider info available
          pdf.text strings[:no_provider_info], size: 11, color: LIGHT_GRAY
        end
      end
      
      # Customer column (right)
      pdf.bounding_box([column_width + 20, start_y], width: column_width) do
        render_section_title(pdf, strings[:customer_info])
        
        pdf.text "#{strings[:name]}: #{quote['customerName']}", size: 11
        pdf.move_down 3
        
        pdf.text "#{strings[:phone]}: #{quote['customerPhone']}", size: 11
        pdf.move_down 3
        
        if quote['customerEmail']
          pdf.text "#{strings[:email]}: #{quote['customerEmail']}", size: 11
          pdf.move_down 3
        end
        
        pdf.text "#{strings[:address]}: #{quote['customerAddress']}", size: 11
      end
      
      # Move cursor to after both columns (estimate space needed)
      pdf.move_cursor_to(start_y - 150) # Approximate height for info sections
    end

    # Render items section
    def render_items(pdf, quote, strings)
      items = quote['items'] || []
      
      items.each_with_index do |item, index|
        pdf.move_down 15
        
        # Item title with bullet
        item_title = format_item_title(item, strings)
        pdf.text "• #{item_title}", size: 15, style: :bold
        pdf.move_down 5
        
        # Type
        type_label = format_service_type(item['type'], strings)
        pdf.text "#{strings[:type]}: #{type_label}", size: 11
        pdf.move_down 3
        
        # Description
        pdf.text "#{strings[:description]}: #{item['description']}", size: 11
        pdf.move_down 3
        
        # Dimensions (if applicable)
        if item['diameterInInches'] || item['heightInFeet']
          dimensions = []
          dimensions << "#{item['diameterInInches']}\" #{strings[:diameter]}" if item['diameterInInches']
          dimensions << "#{item['heightInFeet']}' #{strings[:height]}" if item['heightInFeet']
          pdf.text "#{strings[:dimensions]}: #{dimensions.join(', ')}", size: 11
          pdf.move_down 3
        end
        
        # Risk factors (if any)
        if item['riskFactors'] && !item['riskFactors'].empty?
          risk_labels = item['riskFactors'].map { |rf| format_risk_factor(rf, strings) }
          pdf.text "#{strings[:risk_factors]}: #{risk_labels.join(', ')}", size: 11
          pdf.move_down 3
        end
        
        # Price
        pdf.text "#{strings[:price]}: #{format_price(item['price'])}", 
                 size: 12, style: :bold
      end
      
      # Notes (if any)
      if quote['notes'] && !quote['notes'].empty?
        pdf.move_down 20
        pdf.text "#{strings[:notes]}: #{quote['notes']}", size: 11, color: LIGHT_GRAY
      end
    end

    # Render total in a green bordered box
    def render_total(pdf, quote, strings)
      pdf.bounding_box([pdf.bounds.width - 250, pdf.cursor], width: 250) do
        pdf.stroke_color BRAND_GREEN
        pdf.line_width 2
        pdf.stroke_bounds
        
        pdf.pad(15) do
          pdf.text "#{strings[:total]}: #{format_price(quote['totalPrice'])}", 
                   size: 18, style: :bold, align: :right
        end
      end
    end

    # Render footer with validity note
    def render_footer(pdf, strings)
      pdf.move_down 40
      pdf.text strings[:validity_note], 
               size: 11, align: :center, color: LIGHT_GRAY
      pdf.move_down 5
      pdf.text strings[:thank_you], 
               size: 11, align: :center, color: LIGHT_GRAY
    end

    # Format price in dollars
    def format_price(cents)
      return '$0.00' unless cents
      dollars = cents.to_f / 100
      "$#{format('%.2f', dollars)}"
    end

    # Format date from ISO 8601
    def format_date(iso_date)
      return Time.now.strftime('%Y-%m-%d') unless iso_date
      Time.parse(iso_date).strftime('%Y-%m-%d')
    rescue
      iso_date.split('T').first rescue Time.now.strftime('%Y-%m-%d')
    end

    # Format item title
    def format_item_title(item, strings)
      type_label = format_service_type(item['type'], strings)
      type_label
    end

    # Format service type label
    def format_service_type(type, strings)
      strings[:service_types][type.to_sym] || type.to_s.split('_').map(&:capitalize).join(' ')
    end

    # Format risk factor label
    def format_risk_factor(factor, strings)
      strings[:risk_factor_labels][factor.to_sym] || factor.to_s.split('_').map(&:capitalize).join(' ')
    end

    # English strings
    def english_strings
      {
        quote: 'Quote',
        date: 'Date',
        provider_info: 'Provider Information',
        customer_info: 'Customer Information',
        provider: 'Provider',
        name: 'Name',
        phone: 'Phone',
        email: 'Email',
        website: 'Website',
        address: 'Address',
        no_provider_info: 'Provider information not available',
        requested_work: 'Requested Work',
        type: 'Type',
        description: 'Description',
        dimensions: 'Dimensions',
        diameter: 'diameter',
        height: 'height',
        risk_factors: 'Risk Factors',
        price: 'Price',
        notes: 'Notes',
        total: 'Total',
        validity_note: 'This quote is valid for 14 days.',
        thank_you: 'Thank you for considering our services.',
        service_types: {
          tree_removal: 'Tree Removal',
          pruning: 'Pruning',
          stump_grinding: 'Stump Grinding',
          cleanup: 'Cleanup',
          trimming: 'Trimming',
          emergency_service: 'Emergency Service',
          other: 'Other'
        },
        risk_factor_labels: {
          near_structure: 'Near Structure',
          near_powerlines: 'Near Powerlines',
          leaning: 'Leaning',
          diseased: 'Diseased',
          dead: 'Dead',
          difficult_access: 'Difficult Access',
          other: 'Other'
        }
      }
    end

    # Spanish strings
    def spanish_strings
      {
        quote: 'Cotización',
        date: 'Fecha',
        provider_info: 'Información del Proveedor',
        customer_info: 'Información del Cliente',
        provider: 'Proveedor',
        name: 'Nombre',
        phone: 'Teléfono',
        email: 'Correo',
        website: 'Sitio Web',
        address: 'Dirección',
        no_provider_info: 'Información del proveedor no disponible',
        requested_work: 'Trabajo Solicitado',
        type: 'Tipo',
        description: 'Descripción',
        dimensions: 'Dimensiones',
        diameter: 'diámetro',
        height: 'altura',
        risk_factors: 'Factores de Riesgo',
        price: 'Precio',
        notes: 'Notas',
        total: 'Total',
        validity_note: 'Esta cotización es válida por 14 días.',
        thank_you: 'Gracias por considerar nuestros servicios.',
        service_types: {
          tree_removal: 'Remoción de Árbol',
          pruning: 'Poda',
          stump_grinding: 'Trituración de Tocón',
          cleanup: 'Limpieza',
          trimming: 'Recorte',
          emergency_service: 'Servicio de Emergencia',
          other: 'Otro'
        },
        risk_factor_labels: {
          near_structure: 'Cerca de Estructura',
          near_powerlines: 'Cerca de Líneas Eléctricas',
          leaning: 'Inclinado',
          diseased: 'Enfermo',
          dead: 'Muerto',
          difficult_access: 'Acceso Difícil',
          other: 'Otro'
        }
      }
    end
  end
end

