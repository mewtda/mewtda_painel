class UsersController < ApplicationController
  TEMPORARY_PASSWORD_LENGTH = 12

  before_action :authenticate_user!
  before_action :set_user, only: %i[show edit update destroy reset_password]
  before_action :load_refferences, only: %i[show edit new create]
  before_action :require_admin!

  def index
    @users = User.includes(:client, :profile).paginate(page: params[:page],
                                                       per_page: params_per_page(params[:per_page]))
  end

  def show; end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: 'Usuário criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @user.update(user_params)
      redirect_to users_path, notice: 'Usuário atualizado com sucesso.'
    else
      load_refferences
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to users_path, notice: 'Usuário excluído com sucesso.'
  end

  def reset_password
    return redirect_to(edit_user_path(@user), alert: 'Para trocar a sua própria senha, use Minha conta.') if @user == current_user

    @temporary_password = SecureRandom.base58(TEMPORARY_PASSWORD_LENGTH)
    @user.update!(password: @temporary_password, password_confirmation: @temporary_password)
    response.headers['Cache-Control'] = 'no-store'
    load_refferences
    render :edit
  end

  private

  def load_refferences
    @profiles = Profile.all
    @clients = Client.where(active: true).order(:name)
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :profile_id, :client_id)
  end
end
