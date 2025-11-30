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
    def generate_pdf_en(quote)
      generate_pdf(quote, :en)
    end

    # Generate PDF in Spanish
    def generate_pdf_es(quote)
      generate_pdf(quote, :es)
    end

    private

    # Main PDF generation method
    def generate_pdf(quote, locale)
      pdf = Prawn::Document.new(page_size: 'LETTER', margin: 40)
      
      # Get localized strings
      strings = locale == :es ? spanish_strings : english_strings
      
      # Header with logo and quote info
      render_header(pdf, quote, strings)
      
      # Customer information
      pdf.move_down 30
      render_section_title(pdf, strings[:customer_info])
      render_customer_info(pdf, quote, strings)
      
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
        # Logo on left
        pdf.float do
          pdf.text 'ArborQuote', size: 28, style: :bold, color: BRAND_GREEN
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

    # Render customer information
    def render_customer_info(pdf, quote, strings)
      pdf.text "#{strings[:name]}: #{quote['customerName']}", size: 12
      pdf.move_down 3
      pdf.text "#{strings[:phone]}: #{quote['customerPhone']}", size: 12
      pdf.move_down 3
      pdf.text "#{strings[:address]}: #{quote['customerAddress']}", size: 12
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
        customer_info: 'Customer Information',
        name: 'Name',
        phone: 'Phone',
        address: 'Address',
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
        customer_info: 'Información del Cliente',
        name: 'Nombre',
        phone: 'Teléfono',
        address: 'Dirección',
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

