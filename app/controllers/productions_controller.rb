# app/controllers/productions_controller.rb

require 'prawn'
include ActionView::Helpers::NumberHelper

class ProductionsController < ApplicationController
  before_action :set_production, only: [:show, :edit, :update, :destroy, :verify]
  before_action :set_tailors, only: [:new, :edit, :create, :update]

  def index
    @productions = Production.includes(:tailor, production_products: :product).all

    if params[:tailor_id].present?
      @productions = @productions.where(tailor_id: params[:tailor_id])
    end

    if params[:service_order_number].present?
      @productions = @productions.where("service_order_number LIKE ?", "%#{params[:service_order_number]}%")
    end

    @productions = @productions.order(service_order_number: :desc)
  end

  def show; end

  def verify
    @production = @account.productions.find(params[:id])
  end

  def new
    @production = Production.new
    @production.production_products.build
    @tailors = Tailor.all
  end

  def create
    @production = Production.new(production_params)
    if @production.save
      redirect_to @production, notice: t('.production_created')
    else
      @tailors = Tailor.all
      flash.now[:alert] = t('.creation_failed')
      logger.error("Failed to create production: #{@production.errors.full_messages}")
    end
  end

  def edit
    @production = Production.find(params[:id])
    @tailors = Tailor.all  # Ensure @tailors is set for the edit view
  end

  def update
    @production = Production.find(params[:id])
    if @production.update!(production_params)
      redirect_to @production, notice: t('.production_updated')
    else
      @tailors = Tailor.all
      render :edit
    end
  end

  def destroy
    if @production.destroy
      redirect_to productions_url, notice: t('.production_destroyed')
    else
      redirect_to productions_url, alert: t('.destruction_failed')
    end
  end

  def missing_pieces
    @productions_with_missing_pieces = Production.includes(:tailor, production_products: :product)
                                                 .where(id: ProductionProduct.select(:production_id)
                                                                             .where('quantity > COALESCE(pieces_delivered, 0) + COALESCE(dirty, 0) + COALESCE(error, 0) + COALESCE(discard, 0)'))
                                                 .distinct
                                                 .order(cut_date: :desc, service_order_number: :desc)  # Order by cut_date and service_order_number

    if params[:tailor_id].present?
      @productions_with_missing_pieces = @productions_with_missing_pieces.where(tailor_id: params[:tailor_id])
    end

    # Add status filter
    if params[:status].present?
      case params[:status]
      when 'on_time'
        @productions_with_missing_pieces = @productions_with_missing_pieces.where('expected_delivery_date > ?', Date.today)
      when 'late'
        @productions_with_missing_pieces = @productions_with_missing_pieces.where('expected_delivery_date <= ? AND expected_delivery_date IS NOT NULL', Date.today)
      when 'no_date'
        @productions_with_missing_pieces = @productions_with_missing_pieces.where(expected_delivery_date: nil)
      end
    end

    @tailors_summary = calculate_tailors_summary(@productions_with_missing_pieces)

    respond_to do |format|
      format.html
      format.csv { send_data generate_tailors_summary_csv, filename: "tailors_summary_#{Date.today}.csv" }
    end
  end

  def products_in_production_report
    @products_summary = ProductionProduct.joins(:production, :product)
      .where('quantity > COALESCE(pieces_delivered, 0) + COALESCE(dirty, 0) + COALESCE(error, 0) + COALESCE(discard, 0)')
      .group('products.id, products.name')
      .select('products.id, products.name, SUM(quantity) as total_quantity, SUM(quantity - COALESCE(pieces_delivered, 0) - COALESCE(dirty, 0) - COALESCE(error, 0) - COALESCE(discard, 0)) as total_missing')
      .order('total_quantity DESC')  # Change this line to order by total_quantity in descending order

    respond_to do |format|
      format.html
      format.csv { send_data generate_products_in_production_csv, filename: "products_in_production_#{Date.today}.csv" }
    end
  end

  def service_order_pdf
    @production = Production.find(params[:id])
    pdf = generate_service_order_pdf(@production)
    send_data pdf.render, filename: "service_order_#{@production.service_order_number}.pdf", type: 'application/pdf', disposition: 'inline'
  end

  private

  def set_production
    @production = Production.find(params[:id])
  end

  def set_tailors
    @tailors = Tailor.all
  end

  def production_params
    params.require(:production).permit(
      :cut_date, :tailor_id, :service_order_number, :expected_delivery_date,
      :confirmed, :paid, :consider, :observation, :notions_cost, :fabric_cost, :payment_date,
      production_products_attributes: [:id, :product_id, :quantity, :pieces_delivered, :delivery_date,
                                       :dirty, :error, :discard, :unit_price, :_destroy]
    )
  end

  def calculate_tailors_summary(productions)
    summary = productions.each_with_object({}) do |production, summary|
      tailor_id = production.tailor_id
      summary[tailor_id] ||= { productions_count: 0, total_missing_pieces: 0, products: {} }
      summary[tailor_id][:productions_count] += 1

      production.production_products.each do |pp|
        missing_pieces = pp.quantity - ((pp.pieces_delivered || 0) + (pp.dirty || 0) + (pp.error || 0) + (pp.discard || 0))
        if missing_pieces > 0
          summary[tailor_id][:total_missing_pieces] += missing_pieces
          summary[tailor_id][:products][pp.product_id] ||= 0
          summary[tailor_id][:products][pp.product_id] += missing_pieces
        end
      end
    end

    # Sort products by missing pieces count (descending order)
    summary.each do |tailor_id, tailor_summary|
      tailor_summary[:products] = tailor_summary[:products].sort_by { |_, count| -count }.to_h
    end

    summary
  end

  def generate_tailors_summary_csv
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['Tailor Name', 'Total Productions', 'Total Missing Pieces', 'Products with Missing Pieces']

      @tailors_summary.each do |tailor_id, summary|
        tailor = Tailor.find(tailor_id)
        products_summary = summary[:products].map { |product_id, count| "#{Product.find(product_id).name}: #{count}" }.join(', ')
        
        csv << [
          tailor.name,
          summary[:productions_count],
          summary[:total_missing_pieces],
          products_summary
        ]
      end
    end
  end

  def generate_products_in_production_csv
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['Product Name', 'Total Quantity', 'Total Missing Pieces']

      @products_summary.each do |product|
        csv << [
          product.name,
          product.total_quantity,
          product.total_missing
        ]
      end
    end
  end

  def generate_service_order_pdf(production)
    Prawn::Document.new do |pdf|
      pdf.font_families.update("DejaVu" => {
        normal: "#{Rails.root}/app/assets/fonts/DejaVuSans.ttf",
        bold: "#{Rails.root}/app/assets/fonts/DejaVuSans-Bold.ttf"
      })
      pdf.font "DejaVu"
  
      # Header
      pdf.text "Ordem de serviço N° #{production.service_order_number}", size: 16, style: :bold
      pdf.move_down 20
  
      # Client and Order Details
      pdf.text "Cliente: #{production.tailor.name}", style: :bold
      pdf.text "Endereço: Endereço do cliente" # Replace with actual address when available
      pdf.text "Número da OS: #{production.service_order_number}"
      pdf.text "Data de entrada: #{production.cut_date&.strftime("%d/%m/%Y")}"
      pdf.text "Data prevista: #{production.expected_delivery_date&.strftime("%d/%m/%Y")}"
      pdf.text "Data de conclusão: "
      pdf.move_down 20
  
      # Products
      pdf.text "Peças", size: 14, style: :bold
      pdf.move_down 10
  
      production.production_products.each do |pp|
        pdf.text "Produto: #{pp.product.name}"
        pdf.text "Código: #{pp.product.sku}"
        pdf.text "Quantidade: #{pp.quantity}"
        pdf.text "Preço un.: #{number_to_currency(pp.unit_price)}"
        pdf.text "Valor total: #{number_to_currency(pp.total_price)}"
        pdf.move_down 10
      end
  
      pdf.move_down 20
  
      # Totals
      pdf.text "Total serviços: #{number_to_currency(0)}", align: :right
      pdf.text "Total peças: #{number_to_currency(production.total_price)}", align: :right
      pdf.text "Total da ordem de serviço: #{number_to_currency(production.total_price)}", style: :bold, align: :right
  
      pdf.move_down 30
  
      # Observations
      if production.observation.present?
        pdf.text "Observações do Serviço", style: :bold
        pdf.text production.observation
        pdf.move_down 20
      end
  
      # Signature
      pdf.text "Concordo com os termos descritos acima."
      pdf.move_down 10
      pdf.text "Data _____/_____/_____"
      pdf.move_down 20
      pdf.stroke_horizontal_rule
      pdf.move_down 5
      pdf.text "Assinatura do responsável"
    end
  end
end