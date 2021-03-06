!----------------------------------------------------------------------------------!
!    Copyright (c) 2010-2018 Pauli Parkkinen, Eelis Solala, Wen-Hua Xu,            !
!                            Sergio Losilla, Elias Toivanen, Jonas Juselius        !
!                                                                                  !
!    Permission is hereby granted, free of charge, to any person obtaining a copy  !
!    of this software and associated documentation files (the "Software"), to deal !
!    in the Software without restriction, including without limitation the rights  !
!    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell     !
!    copies of the Software, and to permit persons to whom the Software is         !
!    furnished to do so, subject to the following conditions:                      !
!                                                                                  !
!    The above copyright notice and this permission notice shall be included in all!
!    copies or substantial portions of the Software.                               !
!                                                                                  !
!    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR    !
!    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,      !
!    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE   !
!    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER        !
!    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, !
!    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE !
!    SOFTWARE.                                                                     !
!----------------------------------------------------------------------------------!
!> @file cubeplot.F90
!! Implements IO routines for the Cubeplot file format

!> IO Backend: Gaussian cube files.
!!
!! Gaussian cube files have the following format:
!!
!! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!! L1     : <COMMENT>
!! L2     : <COMMENT>
!! L3     : <N_AT> <ORIG_X> <ORIG_Y> <ORIG_Z>
!! L4     : <NUM_POINTS_DIR_1> <VECTOR1_X> <VECTOR1_Y> <VECTOR1_Z>
!! L5     : <NUM_POINTS_DIR_2> <VECTOR2_X> <VECTOR2_Y> <VECTOR2_Z>
!! L6     : <NUM_POINTS_DIR_3> <VECTOR3_X> <VECTOR3_Y> <VECTOR3_Z>
!! L7     : 0.0 <ATOM1_X> <ATOM1_Y> <ATOM1_Z>
!! L8     : 0.0 <ATOM2_X> <ATOM2_Y> <ATOM2_Z>
!! ...
!! LN_AT  : 0.0 <ATOM{N_AT-6}_X> <ATOM{N_AT-6}_Y> <ATOM{N_AT-6}_Z>
!! LN_AT+1: <CUBE_VAL_1> <CUBE_VAL_2> <CUBE_VAL_3> <CUBE_VAL_4> <CUBE_VAL_5> <CUBE_VAL_6> 
!! ...
!! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!!
!! Everytime the last point of a row (:,j,i) is printed, the line is ended.
!! Further details at <http://local.wasp.uwa.edu.au/~pbourke/dataformats/cube/>.
module cubeplot_m

    use globals_m
    use file_format_class
    use timer_m
    implicit none

    public :: read_cubeplot
    public :: write_cubeplot
    private

contains

    !> Reads a rank-three array from a Cubeplot file.
    !!
    !! @returns `.true.` if reading was successful.
    function read_cubeplot(filename, cp) result(ok)
            character(len=*), intent(in) :: filename
            class(FileFormat)            :: cp
            logical                      :: ok

            integer(INT16) :: num_at 

            call read_grid_cubeplot(filename,&
                    READ_FD,&
                    cp%gdims,&
                    cp%ranges,&
                    num_at,&
                    ok)
            if (ok) then
                allocate(cp%cube(cp%gdims(1), cp%gdims(2), cp%gdims(3)))

                call read_cube_cubeplot(filename,&
                        READ_FD,&
                        cp%cube,&
                        num_at,&
                        ok)
            endif
    end function

    !> Writes a rank-three array to a file.
    !!
    !! Existing files are overwritten.
    subroutine write_cubeplot(filename, cp)
        character(*), intent(in) :: filename
        class(FileFormat), intent(in) :: cp

        integer :: skp=1
        integer :: i, j, k
        real(REAL64) :: step(3)

        open(WRITE_FD, file=trim(filename), form='formatted', status='unknown')
        write(WRITE_FD,*) 'Gaussian cube data, generated by libdage'
        write(WRITE_FD,*) 

        ! This only works for equidistant grids. Non-equidistant grids should be
        ! flagged in grid.f90 and interpolated. grid.f90 should be reworked, big time.
        step(:)=(cp%ranges(2,:)-cp%ranges(1,:))/(cp%gdims(:)-1)

        write(WRITE_FD, '(i5,3f12.6)') 0, cp%ranges(1,:)
        write(WRITE_FD, '(i5,3f12.6)') cp%gdims(1), step(1), 0.d0, 0.d0
        write(WRITE_FD, '(i5,3f12.6)') cp%gdims(2), 0.d0, step(2), 0.d0
        write(WRITE_FD, '(i5,3f12.6)') cp%gdims(3), 0.d0, 0.d0, step(3)

        call progress_bar(0, cp%gdims(1))

        do i=1, cp%gdims(1)
            do j=1, cp%gdims(2)
                do k=1, cp%gdims(3)
                    write(WRITE_FD,'(e20.12)', advance='no') cp%cube(i,j,k)
                    if (mod(k,6) == 0) write(WRITE_FD,*)
                end do
                write(WRITE_FD,*)
            end do
            call progress_bar(i)
        end do

        close(WRITE_FD)
    end subroutine

    !> Low level subroutine to read grid data from a CubePlot file.
    subroutine read_grid_cubeplot(filename, funit, gdims, ranges, num_at, io_ok)
            character(*), intent(in)                :: filename
            integer(INT32), intent(in)              :: funit
            integer(INT32), dimension(3)            :: gdims
            real(REAL64), dimension(2,3)            :: ranges
            integer(INT16)                          :: num_at
            logical                                 :: io_ok

            real(REAL64), dimension(3) :: step
            real(REAL32) :: dummy

            open(funit,file=trim(filename),form='formatted',status='unknown')

            ! Skip two first lines
            read(funit,*,end=42,err=42)
            read(funit,*,end=42,err=42) 

            ! This only works for equidistant grids. Non-equidistant grids should be
            ! flagged in grid.f90 and interpolated. grid.f90 should be reworked, big time.

            read(funit, *,end=42, err=42) num_at, ranges(1,:)
            read(funit, *,end=42, err=42) gdims(1), step(1), dummy, dummy
            read(funit, *,end=42, err=42) gdims(2), dummy, step(2), dummy
            read(funit, *,end=42, err=42) gdims(3), dummy, dummy, step(3)

            ranges(2,:) = step(:)*(gdims(:)-1)+ranges(1,:)

            io_ok = .true.
            close(funit)

            return
42          call perror('Error while reading file '//trim(filename))
            io_ok = .false.
    end subroutine

    !> Low level subroutine to read array data from a CubePlot file.
    subroutine read_cube_cubeplot(filename, funit, cube, num_at, io_ok)
            ! Rejecting lines in the header
            ! Apparently, some programs, like turbomole (or DAGE, before I fixed it!)
            ! wrote the .cub format wrongly adding extra spaces instead of atoms, etc.
            ! The user will be forced to correct the input file!

            character(*), intent(in)                :: filename
            integer(INT32)                          :: funit
            real(REAL64), pointer                   :: cube(:,:,:)
            integer(INT16)                          :: num_at
            logical                                 :: io_ok

            integer(INT32), dimension(3) :: gdims
            integer(INT32) :: i, j, k

            integer(INT32) :: slice_start

            character(BUFLEN) :: line

            gdims(1)=size(cube, 1)
            gdims(2)=size(cube, 2)
            gdims(3)=size(cube, 3)

            open(funit, file=trim(filename), form='formatted', status='unknown')
            !Skip six+num_at lines
            do i=1, 6+num_at
                read(funit, '(a)', end=42, err=42)
            end do

            call progress_bar(0, gdims(1))
            do i=1, gdims(1)
                do j=1, gdims(2)
                    do k=0, (gdims(3)-1)/6
                        read(funit, '(a)',end=42,err=42) line
                        read(line, *, end=42, err=42) cube(i, j, 6*k+1:min(6*k+6,gdims(3)))
                    end do
                end do
                call progress_bar(i)
            end do

            io_ok = .true.
            close(funit)
            return

42          write(ppbuf,'(a,i6)') 'Error while reading file '//trim(filename)//' at line ',&
                    6+num_at+(i-1)*(j-1)*(gdims(3)-1)/6+k+1
            call perror(ppbuf)
            io_ok = .false.
    end subroutine

end module
