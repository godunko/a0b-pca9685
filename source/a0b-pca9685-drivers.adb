------------------------------------------------------------------------------
--                                                                          --
--                           Bare Board Framework                           --
--                                                                          --
------------------------------------------------------------------------------
--
--  Copyright (C) 2019-2024, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

with A0B.Callbacks.Generic_Non_Dispatching;

package body A0B.PCA9685.Drivers is

   OSC_CLOCK : constant := 25_000_000;
   --  Internal oscillator frequency.

   MODE1_Address         :
     constant A0B.I2C.Device_Drivers_8.Register_Address := 16#00#;
   LED0_ON_L_Address     :
     constant A0B.I2C.Device_Drivers_8.Register_Address := 16#06#;
   ALL_LED_ON_H_Address  :
     constant A0B.I2C.Device_Drivers_8.Register_Address := 16#FA#;
   ALL_LED_OFF_H_Address :
     constant A0B.I2C.Device_Drivers_8.Register_Address := 16#FD#;
   PRE_SCALE_Address     :
     constant A0B.I2C.Device_Drivers_8.Register_Address := 16#FE#;

   type MODE1_Register is record
      ALLCALL : Boolean := True;
      SUB3    : Boolean := False;
      SUB2    : Boolean := False;
      SUB1    : Boolean := False;
      SLEEP   : Boolean := True;
      AI      : Boolean := False;
      EXTCLK  : Boolean := False;
      RESTART : Boolean := False;
   end record
     with Size => 8;

   for MODE1_Register use record
      ALLCALL at 0 range 0 .. 0;
      SUB3    at 0 range 1 .. 1;
      SUB2    at 0 range 2 .. 2;
      SUB1    at 0 range 3 .. 3;
      SLEEP   at 0 range 4 .. 4;
      AI      at 0 range 5 .. 5;
      EXTCLK  at 0 range 6 .. 6;
      RESTART at 0 range 7 .. 7;
   end record;

   type OUTNE_Mode is (Off, OUTDRV, High_Impendance)
     with Size => 2;

   type MODE2_Register is record
      OUTNE      : OUTNE_Mode := Off;
      OUTDRV     : Boolean    := True;
      OCH        : Boolean    := False;
      INVRT      : Boolean    := False;
      Reserved_5 : Boolean    := False;
      Reserved_6 : Boolean    := False;
      Reserved_7 : Boolean    := False;
   end record
     with Size => 8;

   for MODE2_Register use record
      OUTNE      at 0 range 0 .. 1;
      OUTDRV     at 0 range 2 .. 2;
      OCH        at 0 range 3 .. 3;
      INVRT      at 0 range 4 .. 4;
      Reserved_5 at 0 range 5 .. 5;
      Reserved_6 at 0 range 6 .. 6;
      Reserved_7 at 0 range 7 .. 7;
   end record;

   type MODE_Register is record
      MODE1 : MODE1_Register;
      MODE2 : MODE2_Register;
   end record;

   procedure On_Completed (Self : in out PCA9685_Controller_Driver'Class);

   package On_Completed_Callbacks is
     new A0B.Callbacks.Generic_Non_Dispatching
           (PCA9685_Controller_Driver, On_Completed);

   procedure On_Initialization
     (Self : in out PCA9685_Controller_Driver'Class);

   procedure On_Configuration
     (Self : in out PCA9685_Controller_Driver'Class);

   package On_Initialization_Callbacks is
     new A0B.Callbacks.Generic_Non_Dispatching
           (PCA9685_Controller_Driver, On_Initialization);

   package On_Configuration_Callbacks is
     new A0B.Callbacks.Generic_Non_Dispatching
           (PCA9685_Controller_Driver, On_Configuration);

   --  function Probe_Synchronous
   --    (Self : in out PCA9685_Controller_Driver'Class) return Boolean;

   ------------------------
   -- Commit_Transaction --
   ------------------------

   overriding procedure Commit_Transaction
     (Self     : in out PCA9685_Controller_Driver;
      Finished : A0B.Callbacks.Callback;
      Success  : in out Boolean) is
   begin
      if Self.Transaction then
         Self.Transaction := False;

         declare
            Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 63)
              with Import, Address => Self.Buffer (Self.Buffer'First)'Address;

         begin
            Self.Write
              (Address      => LED0_ON_L_Address,
               Buffer       => Buffer,
               Status       => Self.Status,
               On_Completed => Finished,
               Success      => Success);

            if not Success then
               raise Program_Error;
            end if;
         end;
      end if;
   end Commit_Transaction;

   ---------------
   -- Configure --
   ---------------

   procedure Configure
     (Self      : in out PCA9685_Controller_Driver'Class;
      Frequency : A0B.Types.Unsigned_16;
      Finished  : A0B.Callbacks.Callback;
      Success   : in out Boolean)
   is
      use type A0B.Types.Unsigned_16;

      MODE        : MODE_Register;
      MODE_Buffer : A0B.Types.Arrays.Unsigned_8_Array (0 .. 1)
        with Import, Address => MODE'Address;

   begin
      if not Success or Self.State /= Ready then
         Success := False;

         return;
      end if;

      Self.Scale :=
        A0B.Types.Unsigned_8
         ((A0B.Types.Unsigned_16 (2 * OSC_CLOCK / 4_096) / Frequency - 1) / 2);
      --  Equation (1) in 7.3.5 assume use of real numbers. Modified version is
      --  used to produce same result with integer operations only.

      Self.Finished := Finished;

      Self.On_Configuration;
      --  Call configuration callback to start device configuration.
      --  XXX Can't be done this way, because might call callback inside.
   end Configure;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Self     : in out PCA9685_Controller_Driver'Class;
      Finished : A0B.Callbacks.Callback;
      Success  : in out Boolean) is
   begin
      if not Success or Self.State /= Initial then
         Success := False;

         return;
      end if;

      Self.Buffer   := (others => <>);
      Self.Status   := (State => A0B.Success, others => <>);
      Self.Finished := Finished;

      Self.On_Initialization;
      --  Call initialization callback to start device initialization.
      --  XXX Can't be done this way, because might call callback inside.
   end Initialize;

   ---------
   -- Off --
   ---------

   overriding procedure Off (Self : in out PCA9685_Channel_Driver) is

      use type A0B.Types.Unsigned_8;

      Base    : constant A0B.Types.Unsigned_8 :=
        A0B.Types.Unsigned_8 (Self.Channel) * 4 + LED0_ON_L_Address;
      Success : Boolean := True;
      Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 3)
        with Import, Address => Self.Controller.Buffer (Self.Channel)'Address;

   begin
      Self.Controller.Buffer (Self.Channel) :=
        (LED_ON_L  => (Count => 0),
         LED_ON_H  => (Count => 0, On => False, others => <>),
         LED_OFF_L => (Count => 0),
         LED_OFF_H => (Count => 0, Off => True, others => <>));

      Self.Controller.Write
        (Address      => Base,
         Buffer       => Buffer,
         Status       => Self.Controller.Status,
         On_Completed =>
           On_Completed_Callbacks.Create_Callback (Self.Controller.all),
         Success      => Success);

      if not Success then
         raise Program_Error;
      end if;
   end Off;

   ---------
   -- Off --
   ---------

   overriding procedure Off (Self : in out PCA9685_Controller_Driver) is
      Value   : constant Registers.LEDXX_Register :=
        (LED_ON_L  => (Count => 0),
         LED_ON_H  => (Count => 0, On => False, others => <>),
         LED_OFF_L => (Count => 0),
         LED_OFF_H => (Count => 0, Off => True, others => <>));
      Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 3)
        with Import, Address => Self.Buffer (Self.Buffer'First)'Address;
      Success : Boolean := True;

   begin
      --  All register values are set, but only 4 bytes are written to the
      --  ALL_LED register.

      for J in Self.Buffer'Range loop
         Self.Buffer (J) := Value;
      end loop;

      Self.Write
        (Address      => ALL_LED_ON_H_Address,
         Buffer       => Buffer,
         --  Operation is asynchronous, and Value is local variable and can't
         --  be used.
         Status       => Self.Status,
         On_Completed => On_Completed_Callbacks.Create_Callback (Self),
         Success      => Success);

      if not Success then
         raise Program_Error;
      end if;
   end Off;

   --------
   -- On --
   --------

   overriding procedure On (Self : in out PCA9685_Channel_Driver) is

      use type A0B.Types.Unsigned_8;

      Base    : constant A0B.Types.Unsigned_8 :=
        A0B.Types.Unsigned_8 (Self.Channel) * 4 + LED0_ON_L_Address;
      Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 3)
        with Import, Address => Self.Controller.Buffer (Self.Channel)'Address;
      Success : Boolean := True;

   begin
      Self.Controller.Buffer (Self.Channel) :=
        (LED_ON_L  => (Count => 0),
         LED_ON_H  => (Count => 0, On => True, others => <>),
         LED_OFF_L => (Count => 0),
         LED_OFF_H => (Count => 0, Off => False, others => <>));
      Self.Controller.Write
        (Address      => Base,
         Buffer       => Buffer,
         Status       => Self.Controller.Status,
         On_Completed =>
           On_Completed_Callbacks.Create_Callback (Self.Controller.all),
         Success      => Success);

      if not Success then
         raise Program_Error;
      end if;
   end On;

   --------
   -- On --
   --------

   overriding procedure On (Self : in out PCA9685_Controller_Driver) is
      Value   : constant Registers.LEDXX_Register :=
        (LED_ON_L  => (Count => 0),
         LED_ON_H  => (Count => 0, On => True, others => <>),
         LED_OFF_L => (Count => 0),
         LED_OFF_H => (Count => 0, Off => False, others => <>));
      Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 3)
        with Import, Address => Self.Buffer (Self.Buffer'First)'Address;
      Success : Boolean := True;

   begin
      --  All register values are set, but only 4 bytes are written to the
      --  ALL_LED register.

      for J in Self.Buffer'Range loop
         Self.Buffer (J) := Value;
      end loop;

      Self.Write
        (Address    => ALL_LED_ON_H_Address,
         Buffer     => Buffer,
         --  Operation is asynchronous, and Value is local variable and can't
         --  be used.
         Status       => Self.Status,
         On_Completed => On_Completed_Callbacks.Create_Callback (Self),
         Success    => Success);

      if not Success then
         raise Program_Error;
      end if;
   end On;

   ------------------
   -- On_Completed --
   ------------------

   procedure On_Completed (Self : in out PCA9685_Controller_Driver'Class) is
   begin
      null;
   end On_Completed;

   ----------------------
   -- On_Configuration --
   ----------------------

   procedure On_Configuration
     (Self : in out PCA9685_Controller_Driver'Class)
   is
      Success : Boolean := True;

   begin
      if Self.Status.State /= A0B.Success then
         raise Program_Error;

         --  return;
      end if;

      case Self.State is
         when Ready =>
            --  Configure PCA9685 to be in sleep state. Sleep state is necessary
            --  to write PRE_SCALE register.
            --
            --  XXX Should some parameters be configurable?

            declare
               MODE : MODE_Register
                 with Import, Address => Self.Aux_Buffer'Address;

            begin
               MODE.MODE1 :=
                 (AI      => True,    --  Default: FALSE
                  --  Enable autoincrement to write many registers by single
                  --  I2C bus write operation.
                  EXTCLK  => False,   --  Default: FALSE
                  SLEEP   => True,    --  Default: TRUE
                  RESTART => False,   --  Default: FALSE
                  SUB1    => False,   --  Default: FALSE
                  SUB2    => False,   --  Default: FALSE
                  SUB3    => False,   --  Default: FALSE
                  ALLCALL => False);  --  Default: TRUE
                  --  ALLCALL address is not used, but may conflict with
                  --  another device on I2C bus.

               MODE.MODE2 :=
                 (OUTDRV     => True,    --  Default: TRUE
                  OUTNE      => Off,     --  Default: OFF
                  OCH        => False,   --  Default: FALSE
                  INVRT      => False,   --  Default: FALSE
                  Reserved_5 => False,   --  Default: FALSE
                  Reserved_6 => False,   --  Default: FALSE
                  Reserved_7 => False);  --  Default: FALSE

               Self.Write
                 (Address      => MODE1_Address,
                  Buffer       => Self.Aux_Buffer (0 .. 1),
                  Status       => Self.Status,
                  On_Completed =>
                    On_Configuration_Callbacks.Create_Callback (Self),
                  Success      => Success);

               Self.State := Configuration_MODE;
            end;

         when Configuration_MODE =>
            --  Configure PRE_SCALE register.

            declare
               PRESCALE : A0B.Types.Unsigned_8
                 with Import, Address => Self.Aux_Buffer'Address;

            begin
               PRESCALE := Self.Scale;

               Self.Write
                 (Address      => PRE_SCALE_Address,
                  Buffer       => Self.Aux_Buffer (0 .. 1),
                  Status       => Self.Status,
                  On_Completed =>
                    On_Configuration_Callbacks.Create_Callback (Self),
                  Success      => Success);

               Self.State := Configuration_PRESCALE;
            end;

         when Configuration_PRESCALE =>
            --  Wakeup controller.

            declare
               MODE1 : MODE1_Register
                 with Import, Address => Self.Aux_Buffer'Address;

            begin
               --  Change SLEEP to False.

               MODE1 :=
                 (AI      => True,    --  Default: FALSE
                  --  Enable autoincrement to write many registers by single
                  --  I2C bus write operation.
                  EXTCLK  => False,   --  Default: FALSE
                  SLEEP   => False,   --  Default: TRUE
                  RESTART => False,   --  Default: FALSE
                  SUB1    => False,   --  Default: FALSE
                  SUB2    => False,   --  Default: FALSE
                  SUB3    => False,   --  Default: FALSE
                  ALLCALL => False);  --  Default: TRUE
                  --  ALLCALL address is not used, but may conflict with
                  --  another device on I2C bus.

               Self.Write
                 (Address      => MODE1_Address,
                  Buffer       => Self.Aux_Buffer (0 .. 0),
                  Status       => Self.Status,
                  On_Completed =>
                    On_Configuration_Callbacks.Create_Callback (Self),
                  Success      => Success);

               Self.State := Configuration_WAKEUP;
            end;

         when Configuration_WAKEUP =>
            Self.State := Ready;

            A0B.Callbacks.Emit_Once (Self.Finished);

         when others =>
            raise Program_Error;
      end case;

      --  Handle transmission failure.

      if not Success then
         raise Program_Error;

         --  return;
      end if;
   end On_Configuration;

   -----------------------
   -- On_Initialization --
   -----------------------

   procedure On_Initialization
     (Self : in out PCA9685_Controller_Driver'Class)
   is
      Success : Boolean := True;

   begin
      if Self.Status.State /= A0B.Success then
         Self.State := Initial;

         A0B.Callbacks.Emit_Once (Self.Finished);

         return;
      end if;

      case Self.State is
   --     --  Do controller's probe.
   --     --  XXX Not implemented in A0B yet
   --
   --     --  Success := Self.Probe_Synchronous;
   --     --
   --     --  if not Success then
   --     --     return;
   --     --  end if;

         when Initial =>
            --  Shutdown all channels. It resets RESTART mode too.
            --
            --  It is down by setting of bit 4 in ALL_LED_OFF_H register.

            declare
               R : Registers.LED_OFF_H_Register
                 with Import, Address => Self.Aux_Buffer'Address;

            begin
               R := (Count => 0, Off => True, others => False);

               Self.Write
                 (Address      => ALL_LED_OFF_H_Address,
                  Buffer       => Self.Aux_Buffer (0 .. 0),
                  Status       => Self.Status,
                  On_Completed =>
                    On_Initialization_Callbacks.Create_Callback (Self),
                  Success      => Success);

               Self.State := Initialization_Shutdown_All;
            end;

         when Initialization_Shutdown_All =>
            --  Configure PCA9685 to almost default configuration and push
            --  into the sleep state. Sleep state is necessary be able to
            --  write PRE_SCALE register.
            --
            --  Difference from the default configuration:
            --   - AI (autoincrement) is enabled
            --   - ALLCALL mode is disable
            --   - PRE_SCALE register is not changed (it will be set by
            --     configuration procedure)

            declare
               MODE : MODE_Register
                 with Import, Address => Self.Aux_Buffer'Address;

            begin
               MODE.MODE1 :=
                 (AI      => True,    --  Default: FALSE
                  --  Enable autoincrement to write many registers by single
                  --  I2C bus write operation.
                  EXTCLK  => False,   --  Default: FALSE
                  SLEEP   => True,    --  Default: TRUE
                  RESTART => False,   --  Default: FALSE
                  SUB1    => False,   --  Default: FALSE
                  SUB2    => False,   --  Default: FALSE
                  SUB3    => False,   --  Default: FALSE
                  ALLCALL => False);  --  Default: TRUE
                  --  ALLCALL address is not used, because it may conflict with
                  --  another device I2C bus.

               MODE.MODE2 :=
                 (OUTDRV     => True,    --  Default: TRUE
                  OUTNE      => Off,     --  Default: OFF
                  OCH        => False,   --  Default: FALSE
                  INVRT      => False,   --  Default: FALSE
                  Reserved_5 => False,   --  Default: FALSE
                  Reserved_6 => False,   --  Default: FALSE
                  Reserved_7 => False);  --  Default: FALSE

               Self.Write
                 (Address      => MODE1_Address,
                  Buffer       => Self.Aux_Buffer (0 .. 1),
                  Status       => Self.Status,
                  On_Completed =>
                    On_Initialization_Callbacks.Create_Callback (Self),
                  Success      => Success);

               Self.State := Initialization_MODE;
            end;

         when Initialization_MODE =>
            Self.State := Ready;

            A0B.Callbacks.Emit_Once (Self.Finished);

         when others =>
            raise Program_Error;
      end case;

      --  Handle transmission failure.

      if not Success then
         raise Program_Error;

         --  return;
      end if;
   end On_Initialization;

   -----------------------
   -- Probe_Synchronous --
   -----------------------

   --  function Probe_Synchronous
   --    (Self : in out PCA9685_Controller_Driver'Class) return Boolean
   --  is
   --     --  Buffer  : A0B.I2C.Unsigned_8_Array (1 .. 0);
   --     --  Status  : aliased A0B.I2C.Device_Drivers_8.Transaction_Status;
   --     --  Await   : aliased BBF.Awaits.Await;
   --     Success : Boolean := True;
   --
   --  begin
   --     --  Self.Write
   --     --    (Buffer       => Buffer,
   --     --     Status       => Status,
   --     --     On_Completed => BBF.Awaits.Create_Callback (Await),
   --     --     Success      => Success);
   --     --
   --     --  if not Success then
   --     --     return;
   --     --  end if;
   --     --
   --     --  BBF.Awaits.Suspend_Till_Callback (Await);
   --
   --     return Success;
   --  end Probe_Synchronous;

   ---------
   -- Set --
   ---------

   overriding procedure Set
     (Self  : in out PCA9685_Channel_Driver;
      On    : A0B.PCA9685.Value_Type;
      Off   : A0B.PCA9685.Value_Type)
   is
      use type A0B.Types.Unsigned_8;

      Base    : constant A0B.Types.Unsigned_8 :=
        A0B.Types.Unsigned_8 (Self.Channel) * 4 + LED0_ON_L_Address;
      Buffer  : A0B.Types.Arrays.Unsigned_8_Array (0 .. 3)
        with Import, Address => Self.Controller.Buffer (Self.Channel)'Address;
      Success : Boolean := True;

   begin
      Self.Controller.Buffer (Self.Channel) :=
        (LED_ON_L  => (Count => Registers.LSB_Count (On mod 256)),
         LED_ON_H  =>
           (Count => Registers.MSB_Count (On / 256), On => False, others => <>),
         LED_OFF_L => (Count => Registers.LSB_Count (Off mod 256)),
         LED_OFF_H =>
           (Count => Registers.MSB_Count (Off / 256), Off => False, others => <>));

      if not Self.Controller.Transaction then
         Self.Controller.Write
           (Address      => Base,
            Buffer       => Buffer,
            Status       => Self.Controller.Status,
            On_Completed =>
              On_Completed_Callbacks.Create_Callback (Self.Controller.all),
            Success      => Success);

         if not Success then
            raise Program_Error;
         end if;
      end if;
   end Set;

   -----------------------
   -- Start_Transaction --
   -----------------------

   overriding procedure Start_Transaction
     (Self : in out PCA9685_Controller_Driver) is
   begin
      Self.Transaction := True;
   end Start_Transaction;

   -------------------
   -- Tick_Duration --
   -------------------

   overriding function Tick_Duration
     (Self : PCA9685_Channel_Driver) return A0B.PCA9685.Tick_Duration_Type is
   begin
      return Self.Controller.Tick_Duration;
   end Tick_Duration;

   -------------------
   -- Tick_Duration --
   -------------------

   overriding function Tick_Duration
     (Self : PCA9685_Controller_Driver)
      return A0B.PCA9685.Tick_Duration_Type is
   begin
      return 1.0 / OSC_CLOCK * (Integer (Self.Scale) + 1);
   end Tick_Duration;

end A0B.PCA9685.Drivers;
