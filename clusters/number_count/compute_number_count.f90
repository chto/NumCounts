! Computing halo number density in a given redshift and observable bin:


    MODULE compute_number_count
    USE legendre_polynomial
    USE hmf_tinker
    USE compute_dVdzdOmega
    USE interface_tools_NC
    USE Phi_of_m
    USE read_data
    IMPLICIT none

    contains

    SUBROUTINE compute_NC(PK,NC)
    implicit none
    type(pk_settings) :: PK
    type(number_counts) :: NC
    type(ini_settings), pointer :: settings
    integer nm, nz, nL ! counter
    integer nz1, nz2, nL1, nL2 ! counter
    double precision sig2_nz1_nz2 ! sigma^2 sample variance
    double precision T0, T1 ! computation time
    integer now0(3),now1(3)
    double precision d_logM,log_M_max,log_M_min,log_mass
    double precision d_lnkappa
    double precision K_ell_sq,sum_over_ell
    double precision volume_z_dz1,volume_z_dz2
    double precision l_tr_min,l_tr_max,NC_Wsrc
    double precision epsabs, epsrel, abserr ! for integral for j_l(rk)*r^2
    integer neval, ier, key ! for integral for j_l(rk)*r^2
    epsabs = 0.0E+00 ! for integral for j_l(rk)*r^2
    epsrel = 0.001E+00 ! for integral for j_l(rk)*r^2
    key = 6 ! for integral for j_l(rk)*r^2

    call CPU_time(T0)
    call itime(now0)

	! If Delta_m is defined get fitting parameters for Tinker hmf for Delta_m
	! otherwise the fitting parameters are computed each time n(M,z) is called
	! for a different redshift for Delta_m=Delta_c/Omega_m(z)
    if (Delta_m .gt. 1.d-3) call Get_fit_param(0.d0)

    ! =========================================================
    ! ALLOCATE POWER SPECTRUM QUANTITIES ======================
    call allocate_pow_spec(PK)
    ! =========================================================
    ! ALLOCATE ARRAYS TO STORE \SIGMA^2(R,z) and derivative ===
    ! this is do to speed up the code =========================
    n_log_M_step=100 ! number of points where compute \sigma^2(R,z) and d\sigma^2(R,z)/dR
    call allocate_Ln_sigma

    log_M_min=log(10.d0**Log10Mminsat+1.d0) ! this must be equal or lower than log_m_lo in dndz(z_reds)
    log_M_max=log(10.**Log10Mmax) ! this must be equal or larger than log_m_up in dndz(z_reds)
    d_logM=(log_M_max-log_M_min)/(n_log_M_step-1.d0) 
    ! Compute and store \sigma^2(R,z) and d\sigma^2(R,z)/dR ===
    !$OMP PARALLEL DO DEFAULT(SHARED), SCHEDULE(STATIC), PRIVATE(nm,nz,log_mass)
    do nm=1,n_log_M_step
        log_mass=log_M_min+d_logM*(nm-1)
        Ln_R_array(nm)=log(M_to_R(exp(log_mass)))
        do nz=1,num_of_z
            Ln_sigma2Rz(nm,nz)=log(sigma_r(M_to_R(exp(log_mass)),redshifts_pk(nz)))
            Ln_dsigma2Rz(nm,nz)=log(-dsig2dr(M_to_R(exp(log_mass)),redshifts_pk(nz))) ! NB disgma2/dR is negative
        end do
!        write(*,*) nm,log_mass
    end do ! end redshift loop
    !$OMP END PARALLEL DO
    ! Compute second derivative for interpolation =============
    do nz=1,PK%num_z
        call spline(Ln_R_array,Ln_sigma2Rz(:,nz),n_log_M_step,cllo,clhi,dd_Ln_sigma2Rz(:,nz))  ! dd Ln(sigma2(R,z))
        call spline(Ln_R_array,Ln_dsigma2Rz(:,nz),n_log_M_step,cllo,clhi,dd_Ln_dsigma2Rz(:,nz))  ! dd Ln(sigma2(R,z))
    end do
    ! =========================================================
    if (use_NC .and. .not. use_only_Poisson .and. use_wind_func) then
    ! =========================================================
    ! Compute the Legendre Polynomials for x=cos(Theta_s) =====
    ! NB the first element is P_l(1)=P_0(cos(theta_s)) ========
    P_l=0.d0
    cos_theta_s(1)= 1.d0 - Delta_Omega/(2.d0*pi_value)
    call p_polynomial_value ( 1, num_of_elle, cos_theta_s, P_l )
    ! =========================================================
    ! Compute integral of r^2 j_l(kr) =========================
    allocate(int_vol_bessel(NC%num_of_z_bin,num_of_elle,num_of_kappas))
    d_lnkappa=(log(0.80d0)-log(1.d-4))/num_of_kappas
    !$OMP PARALLEL DO DEFAULT(SHARED), SCHEDULE(STATIC), PRIVATE(nL,nm,nz,volume_z_dz1,volume_z_dz2)
    do nz=1,NC%num_of_z_bin
        volume_z_dz1=dcom(NC%z_min_array(nz))
        volume_z_dz2=dcom(NC%z_max_array(nz))
        do nL=1,num_of_elle
            ell=nL-1
            do nm=1,num_of_kappas
                k_array(nm)=1.d-4*exp((nm-1)*d_lnkappa)
                kappa=k_array(nm)
                call qag(d_vol_bessel, volume_z_dz1,volume_z_dz2, epsabs, epsrel, key, int_vol_bessel(nz,nL,nm), abserr, neval, ier )
!                write(*,*) nz,ell,nm,kappa,int_vol_bessel(nz,nL,nm)
            end do
        end do
    end do
    !$OMP END PARALLEL DO
    ! =========================================================
    ! =========================================================
    allocate(sum_ell_int_vol_bessel(NC%num_of_z_bin,NC%num_of_z_bin,num_of_kappas))
    do nz1=1,NC%num_of_z_bin
        volume_z_dz1=com_vol(NC%z_min_array(nz1),NC%z_max_array(nz1)) ! Volume of the redshift bin/Delta_Omega
        do nz2=nz1,NC%num_of_z_bin
            volume_z_dz2=com_vol(NC%z_min_array(nz2),NC%z_max_array(nz2)) ! Volume of the redshift bin/Delta_Omega
            do nm=1,num_of_kappas
                sum_over_ell=0.d0
                do ell=1,num_of_elle !NB \ell=ell-1
                    if (ell==1) then ! sarebbe ell=0
                        K_ell_sq=1.d0/4.d0/pi_value
                    else
                        K_ell_sq=pi_value/Delta_Omega/Delta_Omega*(P_l(ell-1)-P_l(ell+1))**2.d0/(2.d0*(ell-1.d0)+1.d0)
                    end if
                    sum_over_ell=sum_over_ell+(int_vol_bessel(nz1,ell,nm)*int_vol_bessel(nz2,ell,nm)*K_ell_sq)/volume_z_dz1/volume_z_dz2
            !       write(*,'(10e16.8)') P_l(ell-1),P_l(ell+1),(P_l(ell-1)-P_l(ell+1))**2.d0,sum_over_ell
                end do
                sum_ell_int_vol_bessel(nz1,nz2,nm)=sum_over_ell
            end do
        end do
    end do
    ! =========================================================
    end if
    ! =========================================================
    if (use_Plobltr) then
    ! I(\Delta_Lambda,M,z)=\int_\Delta_Lambda P(\lambda_obs|m,z)
    nz_step=line_counter_z
    nlogM_step=n_log_M_step
    allocate(int_P_lob_M_z(NC%num_of_L_bin,nz_step,nlogM_step))
    allocate(z_int_P_lobMz(nz_step))
    allocate(M_int_P_lobMz(nlogM_step))
    z_int_P_lobMz=z_int_P_lob
    !$OMP PARALLEL DO DEFAULT(SHARED), SCHEDULE(STATIC), PRIVATE(nL,nm,nz,l_tr_min,l_tr_max)
    do nL=1,NC%num_of_L_bin
        n_L1=nL
        l_tr_min=exp(NC%LnLambda_min_array(n_L1))*0.3d0 ! This should be zero
        l_tr_max=exp(NC%LnLambda_max_array(n_L1))*(-(1.d0/8.d0)*(n_L1-1.d0)+2.d0) ! This should be +infty
        l_tr_max=min(l_tr_max,l_int_P_lob(line_counter_l))
        do nz=1,nz_step
            redshift=z_int_P_lobMz(nz)
            do nm=1,nlogM_step
                M_int_P_lobMz(nm)=log_M_min+d_logM*(nm-1)
                mass=exp(M_int_P_lobMz(nm))
                call trapzd_int(dP_l_ob_M_z, l_tr_min,l_tr_max,int_P_lob_M_z(nL,nz,nm),150)
            end do
        end do
    end do
    !$OMP END PARALLEL DO
    end if


    NC%cov_Li_zi_Lj_zj=0.d0
    NC%n_Li_zj=0.d0
    NC%n_Li_zj_var=0.d0
    NC%mean_m_Li_zj=0.d0
    sig2_nz1_nz2=0.d0

    if (use_NC .and. .not. use_only_Poisson) then
    !$OMP PARALLEL DO DEFAULT(SHARED), SCHEDULE(STATIC), PRIVATE(nL1,nL2,nz1,nz2,sig2_nz1_nz2)
    do nz1=1,NC%num_of_z_bin ! Start loop over redshift bin 1
        n_z1=nz1 ! Assign global variable for integration d_cov_smp_var
        do nz2=nz1,NC%num_of_z_bin ! Start loop over redshift bin 2
            n_z2=nz2 ! Assign global variable for integration d_cov_smp_var
            if (use_wind_func) then
                sig2_nz1_nz2=cov_smp_var((NC%z_min_array(nz1)+NC%z_max_array(nz1))*0.5d0,(NC%z_min_array(nz2)+NC%z_max_array(nz2))*0.5d0) ! full covariance metrix
            else ! Approximate window function with a sphere
                if (nz2 == nz1) sig2_nz1_nz2=sigma_r((3.d0/4.d0/pi_value*Delta_Omega*com_vol(NC%z_min_array(nz1),NC%z_max_array(nz1)))**(1.d0/3.d0),(NC%z_min_array(nz1)+NC%z_max_array(nz1))*0.5d0)
                if (nz2 /= nz1) sig2_nz1_nz2=0.d0
            end if

            NC%cov_Li_zi_Lj_zj(:,nz1,:,nz2)=sig2_nz1_nz2
        end do
    end do
    !$OMP END PARALLEL DO
    end if
    !$OMP PARALLEL DO DEFAULT(SHARED), SCHEDULE(STATIC), PRIVATE(nL1,nz1,NC_Wsrc)
    do nz1=1,NC%num_of_z_bin ! Start loop over redshift bin 1
        do nL1=1,NC%num_of_L_bin ! Start loop over Lambda bin 1
	        ! If Delta_m is defined get fitting parameters for Tinker hmf for Delta_m
	        ! otherwise the fitting parameters are computed each time n(M,z) is called
	        ! for a different redshift for Delta_m=Delta_c/Omega_m(z)
            if (Delta_m_omp .gt. 1.d-3) Delta_m=Delta_m_omp ! I need this line couse Delta_m is OMP THREADPRIVATE
            if (Delta_m .gt. 1.d-3) call Get_fit_param(0.d0)
            task=1 ! NC
            NC%n_Li_zj(nL1,nz1)=n_Lambda_z(nL1,nz1,NC)
            if (use_WL) then
                task=4 ! mean mass
                NC_Wsrc=n_Lambda_z(nL1,nz1,NC) ! W_SOURCE WEIGHTED NC
                task=2
!                NC%mean_m_Li_zj(nL1,nz1)=log10(n_Lambda_z(nL1,nz1,NC)/NC%n_Li_zj(nL1,nz1) ) ! log10<M>
!                NC%mean_m_Li_zj(nL1,nz1)=n_Lambda_z(nL1,nz1,NC)/NC%n_Li_zj(nL1,nz1)/log(10.d0) ! <log10M>
                NC%mean_m_Li_zj(nL1,nz1)=log10(n_Lambda_z(nL1,nz1,NC)/NC_Wsrc) ! log10<Mwsrc>
!                NC%mean_m_Li_zj(nL1,nz1)=n_Lambda_z(nL1,nz1,NC)/NC_Wsrc/log(10.d0) ! <log10Mwsrc>
            end if
            if (use_NC .and. .not. use_only_Poisson) then
                task=3 ! b(M,z)*N_ij
                NC%n_Li_zj_var(nL1,nz1)=n_Lambda_z(nL1,nz1,NC)
            end if
        end do
    end do
    !$OMP END PARALLEL DO
    task=1 ! in verita non necessario perche dopo non chiamo piu' n_lambda_z
    if (use_NC) then
    do nz1=1,NC%num_of_z_bin ! Start loop over redshift bin 1
        do nL1=1,NC%num_of_L_bin ! Start loop over Lambda bin 1
            do nz2=nz1,NC%num_of_z_bin ! Start loop over redshift bin 2
                do nL2=1,NC%num_of_L_bin ! Start loop over Lambda bin 2
                    if (full_NC_cov) then ! full covariance matrix
                        NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)=NC%n_Li_zj_var(nL1,nz1)*NC%n_Li_zj_var(nL2,nz2)*NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2) 
                        if (nz2==nz1 .and. nL2==nL1) NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)=NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)+NC%n_Li_zj(nL1,nz1)
                    else ! only diagonal covariance matrix
                        if (nz2==nz1 .and. nL2==nL1) then
                            if (use_only_Poisson) then
                                NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)=NC%n_Li_zj(nL1,nz1)
                            else
                                NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)=NC%n_Li_zj_var(nL1,nz1)*NC%n_Li_zj_var(nL2,nz2)*NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)+NC%n_Li_zj(nL1,nz1)
                            end if
                        else
                            NC%cov_Li_zi_Lj_zj(nL1,nz1,nL2,nz2)=0.d0
                        end if
                    end if
                end do
            end do
        end do
    end do
    end if

    call CPU_time(T1)
    call itime(now1)
    write(*,*)'computation time1: ',T1-T0,'time end ',now1(2),'m ',now1(3),'s; time start',now0(2),'m',now0(3),'s'
    NC%sigma8_NC=sqrt(sigma2R_at_z(8.d0,0.d0)) ! COMPUTE MY VALUE OF SIGMA8; JUST FOR CONSISTENCY CHECK
    ! =========================================================

    if (use_NC .and. .not. use_only_Poisson .and. use_wind_func) deallocate(int_vol_bessel)
    if (use_NC .and. .not. use_only_Poisson .and. use_wind_func) deallocate(sum_ell_int_vol_bessel)

    if (use_Plobltr) deallocate(int_P_lob_M_z)
    if (use_Plobltr) deallocate(z_int_P_lobMz)
    if (use_Plobltr) deallocate(M_int_P_lobMz)

    call deallocate_pow_spec
    call deallocate_Ln_sigma

    END SUBROUTINE compute_NC

    ! Number density of halo having Lambda in the range =======
    ! LnLambda_min LnLambda_max and z_est within Delta_z_est ==
    ! n(Lambda,z) = int_0^inf dz_true dn(Lambda,z_true)/dz * ==
    ! * Phi(z_true) ; Eq. 16 of Rozo+ 08 ======================
    function n_Lambda_z(n_L,n_z,NC)
    implicit none
    type(number_counts) :: NC
    double precision n_Lambda_z,z_lo,z_up
    integer n_L,n_z
    double precision epsabs, epsrel, abserr
    integer neval, ier
    epsabs = 0.0E+00
    epsrel = 0.001E+00
    
  
    ! Delta Ln_Lambda
    LnLambda_min = NC%LnLambda_min_array(n_L) ! Global Variable used in Phi_M(halo_mass)
    LnLambda_max = NC%LnLambda_max_array(n_L) ! Global Variable used in Phi_M(halo_mass)

    if (add_photoz_scat) then
        z_lo= NC%z_min_array(n_z)-3.5d0*sigma_photoz(NC%z_min_array(n_z))! Test Buzzard
        if (z_lo<0.d0) z_lo=0.d0
        z_up= NC%z_max_array(n_z)+3.5d0*sigma_photoz(NC%z_max_array(n_z))! Test Buzzard
        ! Delta z_photo range
        z_min = NC%z_min_array(n_z) ! Global Variable used in Phi_z(z_true)
        z_max = NC%z_max_array(n_z) ! Global Variable used in Phi_z(z_true)
    else
        z_lo= NC%z_min_array(n_z)
        z_up= NC%z_max_array(n_z)
    end if


    n_L1=n_L ! Global Variable used in Phi_M(halo_mass)

    call qags (integrand_n_Lambda_z, z_lo,z_up, epsabs, epsrel, n_Lambda_z, abserr, neval, ier )
    return
    end function n_Lambda_z
    ! =========================================================

	! integrand of n(Lambda,z): dn(Lambda,z)/dz Phi(z) ========
	FUNCTION integrand_n_Lambda_z(z_true)
    double precision integrand_n_Lambda_z,z_true,area_sterad_at_z
    
    if (use_eff_area) then
        area_sterad_at_z=eff_area_z(z_true)
    else
        area_sterad_at_z=Delta_Omega  !the total angular area ! Test BUZZARD
    end if

    if (task==1 .or. task==3) then
    if (add_photoz_scat) then
        integrand_n_Lambda_z = dndz(z_true)*derivs_com_dis(z_true)*area_sterad_at_z*Phi_z(z_true)
    else
        integrand_n_Lambda_z = dndz(z_true)*derivs_com_dis(z_true)*area_sterad_at_z
    end if
    end if
    
    if (task==2 .or. task==4) then
    if (add_photoz_scat) then
        integrand_n_Lambda_z = dndz(z_true)*derivs_com_dis(z_true)*area_sterad_at_z*Phi_Wsrc_z(z_true)
    else
        integrand_n_Lambda_z = dndz(z_true)*derivs_com_dis(z_true)*area_sterad_at_z*Wsrc_z(z_true)
    end if
    end if
    return
	END FUNCTION integrand_n_Lambda_z
	! =========================================================

	! \int_Delta(z_ob) dz_ob P(z_ob|z_tr) w_src(z_ob)= ========
	! P(z_ob|z_tr)=Normal(mu=z_tr,sigma(z_tr)) ================
	! w_src(z_ob)=b*exp[-a*(z_ob-z*)] =========================
	! a=w_slope; b=w_src_data(z*) =============================
	! a&b fitted from w_src_data=(z/0.16)^(-1 - 4(z-0.16))/ ===
	! [(1+z)^2] ===============================================
	function Phi_Wsrc_z(z_true)
	double precision z_true,z_star,w_slope,w_zstr,sig2_phz, Phi_Wsrc_z, x_min, x_max

    z_star=0.12d0
    w_zstr=1.01510856792d0
    w_slope=8.27390617d0
!    sig2_phz=sigma_photoz(z_true)**2.d0
!    x_min = (z_true-z_max-sig2_phz*w_slope)/sqrt(2.d0*sig2_phz)
!    x_max = (z_true-z_min-sig2_phz*w_slope)/sqrt(2.d0*sig2_phz)
!    Phi_Wsrc_z=0.5d0*w_zstr*dexp(0.5d0*w_slope*(2.d0*z_star+w_slope*sig2_phz-2.d0*z_true))*(derfc(x_min)-derfc(x_max))

    ! INCLUDE PHOTO-Z BIAS AND BOOST
    sig2_phz=(sigma_photoz(z_true)*1.014d0)**2.d0
    x_min = ((z_true+0.002d0)-z_max-sig2_phz*w_slope)/sqrt(2.d0*sig2_phz)
    x_max = ((z_true+0.002d0)-z_min-sig2_phz*w_slope)/sqrt(2.d0*sig2_phz)
    Phi_Wsrc_z=0.5d0*w_zstr*dexp(0.5d0*w_slope*(2.d0*z_star+w_slope*sig2_phz-2.d0*(z_true+0.002d0)))*(derfc(x_min)-derfc(x_max))


	return
	end function Phi_Wsrc_z
	! =========================================================
	
	! \int_Delta(z_ob) dz_ob w_src(z_ob)= =====================
	! w_src(z_ob)=b*exp[-a*(z_ob-z*)] =========================
	! a=w_slope; b=w_src_data(z*) =============================
	! a&b fitted from w_src_data=(z/0.16)^(-1 - 4(z-0.16))/ ===
	! [(1+z)^2] ===============================================
	function Wsrc_z(z_true)
	double precision z_true,z_star,w_slope,w_zstr, Wsrc_z

    z_star=0.12d0
    w_zstr=1.01510856792d0
    w_slope=8.27390617d0
    Wsrc_z=w_zstr/w_slope*(dexp(-w_slope*z_min)-dexp(-w_slope*z_max))

	return
	end function Wsrc_z
	! =========================================================


	! Probability to observe a cluster with z_true ============
	! in the estimated redshift range \Delta_z_est ============
	! Phi_z = int_\Delta_z_est d z_est P(z_est|z_true) ========
	! Eq. 17 of Rozo+ 08 ======================================
	! P(z_est|z_true) = Gaussian ==============================
	function Phi_z(z_true)
	double precision z_true, Phi_z, x_min, x_max

!    x_min = (z_min-z_true)/sqrt(2.d0)/sigma_photoz(z_true)
!    x_max = (z_max-z_true)/sqrt(2.d0)/sigma_photoz(z_true)
!    Phi_z=0.5d0*(derfc(x_min)-derfc(x_max))
    
    ! INCLUDE PHOTO-Z BIAS AND BOOST
    x_min = (z_min-(z_true+0.002d0))/sqrt(2.d0)/(sigma_photoz(z_true)*1.014d0)
    x_max = (z_max-(z_true+0.002d0))/sqrt(2.d0)/(sigma_photoz(z_true)*1.014d0)
    Phi_z=0.5d0*(derfc(x_min)-derfc(x_max))

	return
	end function Phi_z
	! =========================================================

	! Photo-z error ===========================================
	function sigma_photoz(zeta)
	double precision sigma_photoz,zeta
	double precision poly_coeff(4)

	! The best fit values have been obtained fitting the ======
	! SDSS Redmapper v5.10 Cosmological sample with lambda>20 =
	! and 0.1 < z < 0.33 ======================================

	if (LnLambda_max < log(27.9d0)) then
	    poly_coeff=[-1.18159413d0,  1.1060884d0,  -0.24906221d0,  0.02157702d0]
	else if (LnLambda_min >= log(27.9d0) .and. LnLambda_max < log(37.6d0)) then
	    poly_coeff=[-1.22925508d0,  1.11756659d0, -0.25085154d0,  0.02129638d0]
	else if (LnLambda_min >= log(37.6d0) .and. LnLambda_max < log(50.3d0)) then
	    poly_coeff=[-1.26122355d0,  1.12986624d0, -0.25394517d0,  0.0212711d0]
	else if (LnLambda_min >= log(50.3d0) .and. LnLambda_max < log(69.3d0)) then
	    poly_coeff=[-1.16167235d0,  1.05896902d0, -0.23973177d0,  0.02015095d0]
	else ! 69.3< \lambda\ob < 140.0
	    poly_coeff=[-1.20483017d0,  1.0778892d0, -0.24311016d0,  0.02009036d0]
	end if
	
	sigma_photoz = poly_coeff(4) + poly_coeff(3)*zeta + poly_coeff(2)*zeta**2.d0 + poly_coeff(1)*zeta**3.d0
	return
	end function sigma_photoz
	! =========================================================


!	! Photo-z error ===========================================
!	function sigma_photoz(zeta)
!	double precision sigma_photoz,zeta
!	double precision z_pivot,zshift
!	double precision poly_coeff(11)

!	! The best fit values have been obtained fitting the ======
!	! DESY1A1 redMaPPer y1a1_gold_1.0.2b-full_run04_redmapper =
!	!_v6.4.11_lgt20_desformat_catalog.fit =====================
!	! and using 0.10 < z < 0.70 ===============================

!	z_pivot=0.45

!	if (LnLambda_max < log(30.d0)) then
!	    poly_coeff=[ -5.02154555d+04 , -2.68889460d+04 ,  4.36432525d+03 ,  3.48920832d+03, &
!	  -2.26361425d02  ,-1.94147046d+02 ,  1.45430036d+01 ,  6.64474563d+00, &
!	  -3.65942962d-01 , -7.68783737d-02  , 1.48348344d-02]
!	else if (LnLambda_min >= log(30.d0) .and. LnLambda_max < log(45.d0)) then
!	    poly_coeff=[ -4.28552287d+04 , -2.25961624d+04 ,  4.10433144d+03 ,  3.07745885d+03, &
!	  -2.19348367d+02 , -1.78995816d+02  , 1.28045535d+01,   6.23870214d+00, &
!	  -3.18244244d-01 , -7.56867117d-02 ,  1.35264402d-02]
!	else
!	    poly_coeff= [ -4.97585717d+04 , -2.71209769d+04,   4.06900243d+03,   3.53577109d+03, &
!	  -1.55228277d+02  ,-1.90816298d+02  , 9.39707679d+00 ,  6.18852265d+00, &
!	  -2.63374069d-01 , -7.65444985d-02  , 1.23306589d-02]
!	end if

!    if (zeta<0.2d0) zeta=0.2d0 ! no extrapolation outside data range
!    if (zeta>0.7d0) zeta=0.7d0 ! no extrapolation outside data range
!    
!    zshift=zeta-z_pivot
!	sigma_photoz = poly_coeff(11) + poly_coeff(10)*zshift + poly_coeff(9)*zshift**2.d0 + poly_coeff(8)*zshift**3.d0 + poly_coeff(7)*zshift**4.d0 + poly_coeff(6)*zshift**5.d0 + poly_coeff(5)*zshift**6.d0 + poly_coeff(4)*zshift**7.d0 + poly_coeff(3)*zshift**8.d0 + poly_coeff(2)*zshift**9.d0 + poly_coeff(1)*zshift**10.d0
!	return
!	end function sigma_photoz
!	! =========================================================

    ! number density of halo having Lambda in =================
    ! the range Lambda_min LnLambda_max at z ==================
    ! d n(Lambda,z)/dz = int_0^inf dLn(M) M n(M,z) Phi(M) =====
    ! Eq. 2 of Rozo+ 08 =======================================
    function dndz(z_reds)
    implicit none 
    double precision dndz,log_m_lo,log_m_up,z_reds
    double precision epsabs, epsrel, abserr
    integer neval, ier
    epsabs = 0.0E+00
    epsrel = 0.001E+00

    log_m_lo = log(10.**Log10Mminsat+1.d0) ! This +1.d0 is just for numerical reason
    log_m_up = log(10.**Log10Mmax) ! This should be +inf; you can put log_m_up >= ln M(LnLambda_max) + ln M(3*sigma_Ln)

    redshift=z_reds ! Assign the Global Variable
    ! If Delta_c is defined get fitting parameter for Tinker hmf for Delta_m=Delta_c/Omega_m(z)
    if (Delta_c .gt. 1.d-3) call Get_fit_param(redshift)
    call qags (integrand_dndz, log_m_lo,log_m_up, epsabs, epsrel, dndz, abserr, neval, ier )
    return
    end function dndz
    ! =========================================================

	! integrand of dn(Lambda,z)/dz: M n(M,z) Phi(M) ===========
	FUNCTION integrand_dndz(Ln_halo_mass)
    double precision Ln_halo_mass,integrand_dndz
    double precision Phi_M_i,Phi_M_j
    if (task == 1) integrand_dndz = dndM(exp(Ln_halo_mass),redshift)*exp(Ln_halo_mass)*Phi_M(exp(Ln_halo_mass))
    if (task == 2) integrand_dndz = dndM(exp(Ln_halo_mass),redshift)*exp(Ln_halo_mass)**2.d0*Phi_M(exp(Ln_halo_mass)) ! log10<M>
!    if (task == 2) integrand_dndz = dndM(exp(Ln_halo_mass),redshift)*exp(Ln_halo_mass)*Ln_halo_mass*Phi_M(exp(Ln_halo_mass)) ! <log10M>
    if (task == 3) integrand_dndz = dndM(exp(Ln_halo_mass),redshift)*exp(Ln_halo_mass)*Phi_M(exp(Ln_halo_mass))*bias_tin(exp(Ln_halo_mass),redshift)
    if (task == 4) integrand_dndz = dndM(exp(Ln_halo_mass),redshift)*exp(Ln_halo_mass)*Phi_M(exp(Ln_halo_mass))

    if (use_HMF_b_corr) integrand_dndz = integrand_dndz * hmf_baryon_corr(exp(Ln_halo_mass),redshift)

    return
	END FUNCTION integrand_dndz
	! =========================================================

!	! Covariance due to sample variance =======================
	function cov_smp_var(z_reds1,z_reds2)
	implicit none
	double precision cov_smp_var,z_reds1,z_reds2,Ln_k_min,Ln_k_max
    double precision epsabs, epsrel, abserr
    integer neval, ier, key
    epsabs = 0.0E+00
    epsrel = 0.01E+00
    key = 5

    ! Extrema of the logarithmic integral
    ! check this for differnt redshift binning/survey area
	Ln_k_min=log(0.0001d0)
	Ln_k_max=log(0.80d0)
	! Assign Global Variables
	red1=z_reds1 ! redshift considered first bin
	red2=z_reds2 ! redshift considered second bin
	
	
	
    call qag(d_cov_smp_var, Ln_k_min,Ln_k_max, epsabs, epsrel, key, cov_smp_var, abserr, neval, ier )
    cov_smp_var=cov_smp_var*2.d0/pi_value
	return
	end function cov_smp_var

	! d Variance ==============================================
	! This function is valid for a window function ============
	! symmetric around the azimuthal axis with ================
	! apeture cos_theta_s = 1- Delta_Omega / 2*pi =============
	! This function used interpolated integral for ============
	! j_l(kr)*r^2 =============================================
	function d_cov_smp_var(ln_k)
	implicit none
	double precision d_cov_smp_var,ln_k,k_val,sum_over_ell,K_ell_sq,int_bessj_l_kr1,int_bessj_l_kr2
	integer num_of_ell,ll

	k_val=exp(ln_k) ![h/Mpc]
	call ENLGR(k_array,sum_ell_int_vol_bessel(n_z1,n_z2,:),num_of_kappas,k_val,sum_over_ell)
	d_cov_smp_var=sum_over_ell*sqrt(Pk_at_z(k_val,red1)*Pk_at_z(k_val,red2))*k_val**3.d0
	return
	end function d_cov_smp_var


	! Integrand of ============================================
	! \int_r(z_min)^r(z_max) r^2 j_l(r*k) =====================
	function d_vol_bessel(raggio)
	double precision d_vol_bessel,raggio,kerre,bess_ell_kr
	integer elle
	
	elle=ell
	kerre=kappa*raggio
	call BJL(elle,kerre,bess_ell_kr) ! elle-1 perche' inizio da zero la sommatoria
	if (abs(bess_ell_kr) < 1.d-30) then
	    d_vol_bessel=0.d0
	else
	    d_vol_bessel=raggio**2.d0*bess_ell_kr
	end if

	end function d_vol_bessel


    ! Effective bias in Richness bin ==========================
    ! LnLambda_min LnLambda_max and z =========================
    ! b_eff(\Delta Lambda_i,z) = (int_0^inf dM n(M,z)* b(M,z) =
    ! * Phi(M)) / (int_0^inf dM n(M,z)*Phi(M)) ================
    function b_eff_z(n_L,zed,NC)
    implicit none
    type(number_counts) :: NC
    double precision b_eff_z,zed
    double precision int_nbP,int_nP
    integer n_L
    double precision epsabs, epsrel, abserr
    integer neval, ier
    epsabs = 0.0E+00
    epsrel = 0.001E+00

    ! Delta Ln_Lambda
    LnLambda_min = NC%LnLambda_min_array(n_L) ! Global Variable used in Phi_M(halo_mass)
    LnLambda_max = NC%LnLambda_max_array(n_L) ! Global Variable used in Phi_M(halo_mass)

    task=1
    int_nP=dndz(zed)
    task=3
    int_nbP=dndz(zed)
    b_eff_z=int_nbP/int_nP
    task=1
    return
    end function b_eff_z
    ! =========================================================

    ! LN Gaussian prior on nuisance parameters ================
    function LnGauss_prior(x,mean,sig)
    double precision LnGauss_prior,x, mean, sig
    if (sig<=0.d0) then
        LnGauss_prior=0.d0
    else
        LnGauss_prior=-(x-mean)**2.d0/2.d0/sig**2.d0!-0.5d0*log(sig**2.d0) ! last term independent of cosmology and nuisance
    end if
    return 
    end function LnGauss_prior
    ! =========================================================

END MODULE compute_number_count

