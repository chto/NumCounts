module read_data

USE interface_tools_NC
USE utils_NC
implicit none

contains

	!:::::::    Read file to interpolate parameters for Delta_mean in Tinker HMF :::::::::::::::::::::::::::::::::
	! COLUMN: [1] Log Delta_mean ; [2] A ; [3] ddA ; [4] a ; [5] dda ; [6] b ; [7] ddb ; [8] c ; [9] ddc
	! where dd is the second derivative for spile interpolation
	! for Delta > 1600 A0 set to 0.26 w/o spilne interpolation
	subroutine init_tinker_param
	integer i ! counter
	integer tmp_file_unit
	tmp_file_unit=11
    open(tmp_file_unit,file='./modules/data/tinker_param.dat')
    do i=1,num_row
        read(tmp_file_unit,*) Log_delta_input(i),aa_tin0(i),ddaa_tin0(i),a_tin0(i),dda_tin0(i),b_tin0(i),ddb_tin0(i),c_tin0(i),ddc_tin0(i)
    end do
    Log_delta_input=log10(Log_delta_input) ! for interpolation in lin-log space converted to log
	close(tmp_file_unit)
	end subroutine init_tinker_param

	! Read file for the NC data ===============================
	! COLUMN: [1] z_center ; [2] lambda_center ================
	! [3] Halo number density ; [4] NC ========================
	subroutine read_NC_data(NC,file_name)
	type(number_counts) :: NC
	integer i,j,IOstatus ! counter
	integer tmp_file_unit
	double precision :: dummy
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_z_bin ! Start loop over redshift bin
        do j=1,NC%num_of_L_bin ! Start loop over Lambda bin NC%n_Li_zj(nL,nz)
            read(tmp_file_unit,*) NC%z_min_array(i),NC%z_max_array(i),NC%LnLambda_min_array(j),NC%LnLambda_max_array(j),NC%n_Li_zj_data(j,i)
!        write(*,*) 'read values', NC%n_Li_zj_data(j,i)
        end do
    end do
    NC%LnLambda_min_array=log(NC%LnLambda_min_array)
    NC%LnLambda_max_array=log(NC%LnLambda_max_array)
	close(tmp_file_unit)
	end subroutine read_NC_data
	! =========================================================

	! Read file for the WL data ===============================
	! COLUMN: [1] z_inf ; [2] z_sup ; [3] l_inf ===============
	! [4] l_sup ; [4] mean mass in the l/z bin ================
	subroutine read_WL_data(NC,file_name)
	type(number_counts) :: NC
	integer i,j,IOstatus ! counter
	integer tmp_file_unit
	double precision :: dummy
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_z_bin ! Start loop over redshift bin
        do j=1,NC%num_of_L_bin ! Start loop over Lambda bin NC%n_Li_zj(nL,nz)
            read(tmp_file_unit,*) NC%z_min_array(i),NC%z_max_array(i),NC%LnLambda_min_array(j),NC%LnLambda_max_array(j),NC%mean_m_Li_zj_data(j,i)
!        write(*,*) 'read values', NC%mean_m_Li_zj_data(j,i)
        end do
    end do
    NC%LnLambda_min_array=log(NC%LnLambda_min_array)
    NC%LnLambda_max_array=log(NC%LnLambda_max_array)
	close(tmp_file_unit)
	end subroutine read_WL_data
	! =========================================================

	! Read file for the COV WL data ===========================
	! COLUMN: [1] z_inf ; [2] z_sup ; [3] l_inf ===============
	! [4] l_sup ; [4] mean mass in the l/z bin ================
	subroutine read_COV_WL_data(NC,file_name)
	type(number_counts) :: NC
	integer i,IOstatus ! counter
	integer tmp_file_unit
	double precision :: dummy
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_z_bin*NC%num_of_L_bin ! Start loop over redshift bin
        read(tmp_file_unit,*) NC%cov_i_j(i+NC%num_of_L_bin*NC%num_of_z_bin,NC%num_of_L_bin*NC%num_of_z_bin+1:)
!        write(*,*) 'read values COV',i, NC%cov_i_j(i+NC%num_of_L_bin*NC%num_of_z_bin,NC%num_of_L_bin*NC%num_of_z_bin+1:)
        NC%cov_i_j(i+NC%num_of_L_bin*NC%num_of_z_bin,NC%num_of_L_bin*NC%num_of_z_bin+1:)=NC%cov_i_j(i+NC%num_of_L_bin*NC%num_of_z_bin,NC%num_of_L_bin*NC%num_of_z_bin+1:)*WL_COV_scale ! scale the COV matrix
    end do
	close(tmp_file_unit)
	end subroutine read_COV_WL_data
	! =========================================================


	! Read file for the \int_Delta_lambda_i d\lambda_obs ======
	!P(\lambda_obs|\lambda_tr,z_tr) ===========================
	subroutine read_int_P_lob_ltr(num_l_bin,version_number)
	integer i,l,m! counter
	integer num_l_bin,tmp_file_unit
	character(len=300) :: file_name_m
	character(len=10) :: version_number
	character(LEN=5)  m_bin

	tmp_file_unit=11
	
    file_name_m='./modules/data/z_in_talbe_'//trim(version_number)//'.dat'
    call count_line_num(file_name_m,line_counter_z)
    file_name_m='./modules/data/l_in_talbe_'//trim(version_number)//'.dat'
    call count_line_num(file_name_m,line_counter_l)
!    write(*,*) line_counter_l,line_counter_z
!    stop 24
    
    ! Save the values in two arrays ===========================
    allocate(int_P_lob_ltr(num_l_bin,line_counter_z,line_counter_l))
    allocate(z_int_P_lob(line_counter_z))
    allocate(l_int_P_lob(line_counter_l))


    open(tmp_file_unit,file='./modules/data/z_in_talbe_'//trim(version_number)//'.dat')
    read(tmp_file_unit,*) z_int_P_lob
    close(tmp_file_unit)


    open(tmp_file_unit,file='./modules/data/l_in_talbe_'//trim(version_number)//'.dat')
    read(tmp_file_unit,*) l_int_P_lob
    close(tmp_file_unit)
!    write(*,*) line_counter_z,line_counter_l
    
    do m=1,num_l_bin
        write(m_bin,'(i1)') m ! write m in char variable
        m_bin=trim(adjustl(m_bin))
        file_name_m='./modules/data/int_P_lob_ltr_ztr_Deltal_'//trim(m_bin)//'_'//trim(version_number)//'.dat'
!        write(*,*) file_name_m
        open(tmp_file_unit,file=file_name_m)
        do i=1,line_counter_z
            read(tmp_file_unit,*) int_P_lob_ltr(m,i,:)
!            write(*,*) 'read values', int_P_lob_ltr(m,i,:)
!            stop 24
        end do
        close(tmp_file_unit)
    end do

	end subroutine read_int_P_lob_ltr
	! =========================================================


	! Read file for skew-gauss parametes ======================
	subroutine read_skew_gauss_table
	integer i ! counter
	integer tmp_file_unit

	tmp_file_unit=11
	
	n_sig_grid=14
	n_lsat_grid=42
	
	allocate(sig_intr_grid(n_sig_grid))
	allocate(l_sat_grid(n_lsat_grid))
    open(tmp_file_unit,file='./modules/data/sig_intr_grid5.dat')
    read(tmp_file_unit,*) sig_intr_grid
    close(tmp_file_unit)
    open(tmp_file_unit,file='./modules/data/l_sat_grid5.dat')
    read(tmp_file_unit,*) l_sat_grid
    close(tmp_file_unit)

	allocate(skew_table(n_lsat_grid,n_sig_grid))
    open(tmp_file_unit,file='./modules/data/skew_table5.dat')
    do i=1,n_sig_grid
        read(tmp_file_unit,*) skew_table(:,i)
!        write(*,*) skew_table(:,i)
    end do
    close(tmp_file_unit)

	allocate(sig_skew_table(n_lsat_grid,n_sig_grid))
    open(tmp_file_unit,file='./modules/data/sig_skew_table5.dat')
    do i=1,n_sig_grid
        read(tmp_file_unit,*) sig_skew_table(:,i)
!        write(*,*) sig_skew_table(:,i)
    end do
    close(tmp_file_unit)

	allocate(ddskew_table(n_lsat_grid,n_sig_grid))
	allocate(ddsig_skew_table(n_lsat_grid,n_sig_grid))
    do i=1,n_sig_grid
        call spline(l_sat_grid,skew_table(:,i),n_lsat_grid,cllo,clhi,ddskew_table(:,i))
        call spline(l_sat_grid,sig_skew_table(:,i),n_lsat_grid,cllo,clhi,ddsig_skew_table(:,i))
    end do

	end subroutine read_skew_gauss_table
	! =========================================================
	
	! Count the number of line of the file ====================
	subroutine count_line_num(file_name,num_lines)
	integer i,IOstatus ! counter
	integer tmp_file_unit
	integer, INTENT(OUT) :: num_lines
	double precision :: dummy
	character(len=300) :: file_name
	tmp_file_unit=11

    open(tmp_file_unit,file=file_name)
    IOstatus=0
    num_lines=0
    do while (IOstatus == 0)
        read(tmp_file_unit,*,IOSTAT=IOstatus) dummy
        if (IOstatus .gt. 0) then
            write(*,*) "error reading file: ",file_name
            stop 24
        end if
        if (IOstatus == 0) num_lines=num_lines+1
    end do
    close(tmp_file_unit)
	end subroutine count_line_num
	! =========================================================
	
	! Read file for dLog10M/dOmega_m per l bin ================
	subroutine read_dlogMdOm(NC,file_name,dlogdom)
	type(number_counts) :: NC
	integer i,IOstatus ! counter
	integer tmp_file_unit
	double precision , INTENT(OUT) :: dlogdom(NC%num_of_L_bin)
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_L_bin ! Start loop over redshift bin
        read(tmp_file_unit,*) dlogdom(i)
!        write(*,*) 'read dlogdom',i, dlogdom(i)
    end do
	close(tmp_file_unit)

	end subroutine read_dlogMdOm
	! =========================================================

	! Read file for the COV HMF NUISANCE ======================
	subroutine read_COV_HMF_nuis(file_name,cov_sq)
	integer i,IOstatus ! counter
	integer tmp_file_unit
	double precision, dimension(2,2), INTENT(OUT) :: cov_sq
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,2
        read(tmp_file_unit,*) cov_sq(i,:)
!        write(*,*) 'read values COV(s,q)',i, cov_sq(i,:)
    end do
	close(tmp_file_unit)
	end subroutine read_COV_HMF_nuis
	! =========================================================

	! Read file for the COV NC MISCENTERING ===================
	subroutine read_COV_NCMISS_data(NC,file_name)
	type(number_counts) :: NC
	integer i,IOstatus ! counter
	integer tmp_file_unit
	double precision :: dummy
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_z_bin*NC%num_of_L_bin ! Start loop over redshift bin
        read(tmp_file_unit,*) NC%cov_misc_i_j(i,:)
!        write(*,*) 'read values COV',i, sqrt(NC%cov_misc_i_j(i,:))
    end do
	close(tmp_file_unit)
	end subroutine read_COV_NCMISS_data
	! =========================================================

	! Read file for the NC data ===============================
	subroutine read_bins(NC,file_name)
	type(number_counts) :: NC
	integer i,j,IOstatus ! counter
	integer tmp_file_unit
	double precision :: dummy
	character(len=300) file_name
	tmp_file_unit=11
    ! Save the values in a matrix =============================
    open(tmp_file_unit,file=file_name)
    do i=1,NC%num_of_z_bin ! Start loop over redshift bin
        do j=1,NC%num_of_L_bin ! Start loop over Lambda bin NC%n_Li_zj(nL,nz)
            read(tmp_file_unit,*) NC%z_min_array(i),NC%z_max_array(i),NC%LnLambda_min_array(j),NC%LnLambda_max_array(j)
        end do
    end do
    NC%LnLambda_min_array=log(NC%LnLambda_min_array)
    NC%LnLambda_max_array=log(NC%LnLambda_max_array)
	close(tmp_file_unit)
	end subroutine read_bins
	! =========================================================
end module read_data
