#include "ShipsCommon.as";
#include "HumanCommon.as";
#include "BlockProduction.as";
#include "PropellerForceCommon.as";

const u16 COUPLINGS_COOLDOWN = 8 * 30;
const u16 CREW_COUPLINGS_LEASE = 20 * 30;
const u16 UNUSED_RESET = 5 * 30;
const u8 CANNON_FIRE_CYCLE = 15;
const f32 seat_boost = 0.5f; // 0.1f is 10%

void onInit(CBlob@ this)
{
	this.set_f32("weight", 0.5f);
	
	//Set Owner/couplingsCooldown
	if (isServer())
	{
		this.set("couplingCooldown", 0);
			
		u16[] left_propellers, strafe_left_propellers, strafe_right_propellers, right_propellers, up_propellers, down_propellers, machineguns, cannons;					
		this.set("left_propellers", left_propellers);
		this.set("strafe_left_propellers", strafe_left_propellers);
		this.set("strafe_right_propellers", strafe_right_propellers);
		this.set("right_propellers", right_propellers);
		this.set("up_propellers", up_propellers);
		this.set("down_propellers", down_propellers);
		this.set("machineguns", machineguns);
		this.set("cannons", cannons);
		
		this.set_bool("kUD", false);
		this.set_bool("kLR", false);
		this.set_u32("lastCannonFire", getGameTime());
		this.set_u8("cannonFireIndex", 0);
		this.set_u32("lastActive", getGameTime());
		this.set_u32("lastOwnerUpdate", 0);
	}
	
	this.set_string("seat label", "Co-pilot Seat");
	this.set_bool("canProduceCoupling", false);
	this.set_u8("seat icon", 7);
	this.Tag("control");
	this.Tag("seat");
	this.Tag("ramming");
	
	//anim
	CSprite@ sprite = this.getSprite();
	//default
	{
		Animation@ anim = sprite.addAnimation("default", 0, false);
		anim.AddFrame(0);
	}
	//folding
	{
		Animation@ anim = sprite.addAnimation("fold", 4, false);
		int[] frames = {0, 1, 2, 3, 4};
		anim.AddFrames(frames);
	}
}

void onTick(CBlob@ this)
{
	const int seatColor = this.getShape().getVars().customData;
	if (seatColor <= 0) return;	

	const u32 gameTime = getGameTime();
	const u8 teamNum = this.getTeamNum();
	const string seatOwner = this.get_string("playerOwner");
	
	if (isServer())
	{
		//clear ownership on player leave/change team or seat not used
		CPlayer@ ownerPlayer = getPlayerByUsername(seatOwner);
		if (ownerPlayer is null || ownerPlayer.getTeamNum() != teamNum || gameTime - this.get_u32("lastActive") > UNUSED_RESET)
		{
			server_setOwner(this, "");
			//print("** Clearing ownership: " + seatOwner + (ownerPlayer is null ? " left" : " changed team/not used"));
		}
		
		//fail-safe. force owner update
		if (gameTime - this.get_u32("lastOwnerUpdate") > 90)
		{
			this.Sync("playerOwner", true);
			this.set_u32("lastOwnerUpdate", gameTime);
		}
	}

	CSprite@ sprite = this.getSprite();
	sprite.SetAnimation(seatOwner != "" ? "default": "fold"); //update sprite

	Ship@ ship = getShipSet().getShip(seatColor);
	if (ship is null) return;
	
	AttachmentPoint@ seat = this.getAttachmentPoint(0);
	CBlob@ occupier = seat.getOccupied();
	if (occupier !is null)
	{
		const f32 angle = this.getAngleDegrees();
		occupier.setAngleDegrees(angle);
				
		CPlayer@ player = occupier.getPlayer();
		if (player is null)	return;

		CRules@ rules = getRules();
		CHUD@ HUD = getHUD();
		const string occupierName = player.getUsername();
		const u8 occupierTeam = occupier.getTeamNum();
		const bool isCopilot = ship.copilot == occupierName || ship.copilot == "*" || ship.copilot.isEmpty();
		const bool canHijack = seatOwner == ship.copilot && occupierTeam != teamNum;
			
		const bool up = occupier.isKeyPressed(key_up);
		const bool left = occupier.isKeyPressed(key_left);
		const bool right = occupier.isKeyPressed(key_right);
		const bool down = occupier.isKeyPressed(key_down);
		const bool space = occupier.isKeyPressed(key_action3);	
		const bool inv = occupier.isKeyPressed(key_inventory);
		const bool strafe = occupier.isKeyPressed(key_pickup) || occupier.isKeyPressed(key_taunts);
		const bool left_click = occupier.isKeyPressed(key_action1);	
		const bool right_click = occupier.isKeyPressed(key_action2);	

		//client-side couplings managing functions
		if (player.isMyPlayer())
		{
			//show help tip
			occupier.set_bool("drawSeatHelp", !ship.copilot.isEmpty() && occupierTeam == teamNum && !isCopilot && occupierName == seatOwner);
			
			//couplings help tip
			occupier.set_bool("drawCouplingsHelp", this.get_bool("canProduceCoupling"));

			//gather couplings and flak
			CBlob@[] couplings, allBoosters, flak;
			const u16 blocksLength = ship.blocks.length;
			for (u16 i = 0; i < blocksLength; ++i)
			{
				ShipBlock@ ship_block = ship.blocks[i];
				if (ship_block is null) continue;

				CBlob@ block = getBlobByNetworkID(ship_block.blobID);
				if (block is null) continue;
				
				//gather couplings
				if (block.hasTag("coupling") && !block.hasTag("_coupling_hitspace"))
					couplings.push_back(block);
				else if (block.hasTag("booster"))
					allBoosters.push_back(block);
				else if (block.hasTag("flak"))
					flak.push_back(block);
			}
			
			const u16 couplingsLength = couplings.length;
			const u16 flakLength = flak.length;

			//Show coupling/flak/repulsor buttons on spacebar down
			if (occupier.isKeyJustPressed(key_action3))
			{
				//couplings on ship
				for (u16 i = 0; i < couplingsLength; ++i)
				{
					CBlob@ c = couplings[i];
					if (!c.isOnScreen()) continue;
					
					const bool isOwner = c.get_string("playerOwner") == occupierName;

					if (isCopilot)
					{
						CButton@ button;
						const bool oldEnough = c.getTickSinceCreated() > CREW_COUPLINGS_LEASE || c.getTeamNum() != occupierTeam;
						if ((isOwner || oldEnough))
						{
							@button = occupier.CreateGenericButton(isOwner ? 2 : 1, Vec2f_zero, c, c.getCommandID("decouple"), isOwner ? "Decouple" : "Decouple (crew's)");
						}
						else
							@button = occupier.CreateGenericButton(0, Vec2f_zero, c, 0, "Can't decouple yet (crew's)");
							
						if (button !is null) 
						{
							button.enableRadius = 999.0f;
							button.radius = 1.0f; //radius change for engine issue (remove this if engine gets fixed) (shut yo goofy ass its ur brain issue m8)
						}
					} 
					else if (isOwner)
					{
						CButton@ button = occupier.CreateGenericButton(2, Vec2f_zero, c, c.getCommandID("decouple"), "Decouple");
						if (button !is null)
						{
							button.enableRadius = 999.0f;
							button.radius = 1.0f;
						}
					}
				}
				
				//repulsors on screen
				CBlob@[] repulsors;	
				getBlobsByTag("repulsor", @repulsors);
				const u16 repulsorLength = repulsors.length;
				for (u16 i = 0; i < repulsorLength; ++i)
				{
					CBlob@ r = repulsors[i];
					const int color = r.getShape().getVars().customData;
					if (color > 0 && r.isOnScreen() && !r.hasTag("activated") && r.get_string("playerOwner") == occupierName || (isCopilot && seatColor == color))
					{
						CButton@ button = occupier.CreateGenericButton(8, Vec2f_zero, r, r.getCommandID("chainReaction"), "Activate");
						if (button !is null)
						{
							button.enableRadius = 999.0f;
							button.radius = 1.0f;
						}
					}
				}

				// boosters
				CBlob@[] boosters;	
				getBlobsByTag("booster", @boosters);
				const u16 boosterLength = boosters.length;
				for (u16 i = 0; i < boosterLength; ++i)
				{
					CBlob@ r = boosters[i];
					const int color = r.getShape().getVars().customData;
					if (r.hasTag("activated") || r.get_u32("cooldown") > getGameTime()) continue;
					if (color > 0 && r.isOnScreen() && r.get_string("playerOwner") == occupierName || (isCopilot && seatColor == color))
					{
						CButton@ button = occupier.CreateGenericButton(8, Vec2f_zero, r, r.getCommandID("chainReaction"), "Activate");
						if (button !is null)
						{
							button.enableRadius = 999.0f;
							button.radius = 1.0f;
						}
					}
				}
				
				//flak on ship: detach player
				if (isCopilot)
				{
					for (u16 i = 0; i < flakLength; ++i)
					{
						CBlob@ f = flak[i];
						if (f.hasAttached())
						{
							CButton@ button = occupier.CreateGenericButton(5, Vec2f_zero, f, f.getCommandID("clear attached"), "Push Crewmate Out");
							if (button !is null)
							{
								button.enableRadius = 999.0f;
								button.radius = 1.0f;
							}
						}
					}
				}
			}
			
			//hax: update can't-decouplers
			if (isCopilot && space)
			{
				for (u16 i = 0; i < couplingsLength; ++i)
				{
					CBlob@ c = couplings[i];
					if (c.get_string("playerOwner") != occupierName && c.getTickSinceCreated() == CREW_COUPLINGS_LEASE)
					{
						occupier.ClickClosestInteractButton(c.getPosition(), 0.0f);
						
						CButton@ button = occupier.CreateGenericButton(1, Vec2f_zero, c, c.getCommandID("decouple"), "Decouple (crew's)");
						if (button !is null) button.enableRadius = 999.0f;
					}
				}
			}

			//Kill coupling/turret buttons on spacebar up
			if (occupier.isKeyJustReleased(key_action3))
				occupier.ClearButtons();
		
			//Release all couplings on spacebar + right click
			if (space && HUD.hasButtons() && right_click)
			{
				for (u16 i = 0; i < allBoosters.length; ++i)
				{
					CBlob@ b = allBoosters[i];
					if (b.get_string("playerOwner") == occupierName && !b.hasTag("activated") && b.get_u32("cooldown") < getGameTime())
					{
						b.SendCommand(b.getCommandID("chainReaction"));
					}
				}
			}
		}
		
		//******svOnly below
		if (!isServer()) return;
	
		if (occupierName == seatOwner)
			this.set_u32("lastActive", gameTime);
		else
			this.set_u32("lastActive", Maths::Max(0, this.get_u32("lastActive") - 3));//resets 4x faster if enemy is using it
			
		if (seatOwner.isEmpty())//Re-set empty seat's owner to occupier
		{
			//print("** Re-setting seat owner: " + occupierName);
			server_setOwner(this, occupierName);
		}	
		
		//Produce coupling
		u32 couplingCooldown;
		this.get("couplingCooldown", couplingCooldown);
		const bool canProduceCoupling = gameTime > couplingCooldown;
		this.set_bool("canProduceCoupling", canProduceCoupling);
		this.Sync("canProduceCoupling", true); //-1891382656 HASH
		
		if (inv && canProduceCoupling && !Human::wasHoldingBlocks(occupier) && !Human::isHoldingBlocks(occupier))
		{
			this.set("couplingCooldown", gameTime + COUPLINGS_COOLDOWN);
			ProduceBlock(rules, occupier, "coupling", 2);
		}
		
		//update if ships changed
		if (this.get_bool("updateBlock") && (gameTime + this.getNetworkID()) % 10 == 0)
			updateArrays(this, ship);
		
		if (space && left_click)//so when a player undocks the ship stops
		{
			this.set_bool("kUD", true);
			this.set_bool("kLR", true);
		}
		
		//ship controlling: only ship 'captain' OR enemy can steer /direct fire
		if (isCopilot || canHijack)
		{
			// gather propellers, couplings, machineguns and cannons
			u16[] left_propellers, strafe_left_propellers, strafe_right_propellers, right_propellers, up_propellers, down_propellers, machineguns, cannons;					
			this.get("left_propellers", left_propellers);
			this.get("strafe_left_propellers", strafe_left_propellers);
			this.get("strafe_right_propellers", strafe_right_propellers);
			this.get("right_propellers", right_propellers);
			this.get("up_propellers", up_propellers);
			this.get("down_propellers", down_propellers);
			this.get("machineguns", machineguns);
			this.get("cannons", cannons);

			//propellers
			const bool teamInsensitive = !ship.isMothership || ship.copilot != "*"; //it's a mini or mship isn't merged with another mship (every side controls their props)
			
			const u16 upPropLength = up_propellers.length;
			const u16 downPropLength = down_propellers.length;
			const u16 leftPropLength = left_propellers.length;
			const u16 rightPropLength = right_propellers.length;

			//reset			
			if (this.get_bool("kUD") && !up && !down)
			{
				this.set_bool("kUD", false);
				
				for (u16 i = 0; i < upPropLength; ++i)
				{
					CBlob@ prop = getBlobByNetworkID(up_propellers[i]);
					if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
					{
						prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
					}
				}
				for (u16 i = 0; i < downPropLength; ++i)
				{
					CBlob@ prop = getBlobByNetworkID(down_propellers[i]);
					if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
					{
						prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
					}
				}
			}
			if (this.get_bool("kLR") && (strafe || (!left && !right)))
			{
				this.set_bool("kLR", false);
				
				for (u16 i = 0; i < leftPropLength; ++i)
				{
					CBlob@ prop = getBlobByNetworkID(left_propellers[i]);
					if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
					{
						prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
					}
				}
				for (u16 i = 0; i < rightPropLength; ++i)
				{
					CBlob@ prop = getBlobByNetworkID(right_propellers[i]);
					if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
					{
						prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
					}
				}
			}

			if (!ship.captains_controls)
			{
				//reset			
				if (!up && !down)
				{
					this.set_bool("kUD", false);

					for (u16 i = 0; i < upPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(up_propellers[i]);
						if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_f32("power", 0);
							prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
						}
					}
					for (u16 i = 0; i < downPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(down_propellers[i]);
						if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_f32("power", 0);
							prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
						}
					}
				}
				if ((strafe || (!left && !right)))
				{
					this.set_bool("kLR", false);

					for (u16 i = 0; i < leftPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(left_propellers[i]);
						if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_f32("power", 0);
							prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
						}
					}
					for (u16 i = 0; i < rightPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(right_propellers[i]);
						if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_f32("power", 0);
							prop.set_f32("powerFactor", prop.get_f32("initPowerFactor"));
						}
					}
				}

				f32 power, reverse_power;
				if (ship.isMothership)
				{
					power = -1.05f;
					reverse_power = 0.15f;
				}
				else
				{
					power = -1.0f;
					reverse_power = 0.1f;
				}

				//movement modes
				if (up || down)
				{
					this.set_bool("kUD", true);

					for (u16 i = 0; i < upPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(up_propellers[i]);
						if (prop is null) continue;

						if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_u32("onTime", gameTime);
							f32 power_factor = prop.hasTag("booster") && !prop.hasTag("activated") ? prop.get_f32("powerFactor")/2 : prop.get_f32("powerFactor");
							prop.set_f32("power", up ? power * power_factor : reverse_power * power_factor);
						}
					}
					for (u16 i = 0; i < downPropLength; ++i)
					{
						CBlob@ prop = getBlobByNetworkID(down_propellers[i]);
						if (prop is null) continue;

						if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
						{
							prop.set_u32("onTime", gameTime);
							f32 power_factor = prop.hasTag("booster") && !prop.hasTag("activated") ? prop.get_f32("powerFactor")/2 : prop.get_f32("powerFactor");
							prop.set_f32("power", down ? power * power_factor : reverse_power * power_factor);
						}
					}
				}

				if (left || right)
				{
					this.set_bool("kLR", true);

					if (!strafe)
					{
						for (u16 i = 0; i < leftPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(left_propellers[i]);
							if (prop is null) continue;

							if (seatColor == prop.getShape().getVars().customData &&  (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_u32("onTime", gameTime);
								f32 power_factor = prop.hasTag("booster") && !prop.hasTag("activated") ? prop.get_f32("powerFactor")/2 : prop.get_f32("powerFactor");
								prop.set_f32("power", left ? power * power_factor : reverse_power * power_factor);
							}
						}
						for (u16 i = 0; i < rightPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(right_propellers[i]);
							if (prop is null) continue;

							if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_u32("onTime", gameTime);
								f32 power_factor = prop.hasTag("booster") && !prop.hasTag("activated") ? prop.get_f32("powerFactor")/2 : prop.get_f32("powerFactor");
								prop.set_f32("power", right ? power * power_factor : reverse_power * power_factor);
							}
						}
					}
					else
					{
						const u8 maxStrafers = Maths::Round(Maths::FastSqrt(ship.mass)/3.0f);
						const u16 strLeftPropLength = strafe_left_propellers.length;
						for (u16 i = 0; i < strLeftPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(strafe_left_propellers[i]);
							if (prop is null) continue;
							if (prop.hasTag("booster") && (!prop.hasTag("activated") || prop.get_u32("cooldown") > getGameTime())) continue;
							const f32 oDrive = i < maxStrafers ? 2.0f : 1.0f;
							if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_u32("onTime", gameTime);
								prop.set_f32("power", left ? oDrive * power * prop.get_f32("powerFactor") : reverse_power * prop.get_f32("powerFactor"));
							}
						}
						const u16 strRightPropLength = strafe_right_propellers.length;
						for (u16 i = 0; i < strRightPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(strafe_right_propellers[i]);
							if (prop is null) continue;
							if (prop.hasTag("booster") && (!prop.hasTag("activated") || prop.get_u32("cooldown") > getGameTime())) continue;
							const f32 oDrive = i < maxStrafers ? 2.0f : 1.0f;
							if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_u32("onTime", gameTime);
								prop.set_f32("power", right ? oDrive * power * prop.get_f32("powerFactor") : reverse_power * prop.get_f32("powerFactor"));
							}
						}
					}
				}
			}
			else
			{
				f32 power = 1.0f + seat_boost;
				if (occupier !is null)
				{
					//movement modes
					if (up || down)
					{
						this.set_bool("kUD", true);

						for (u16 i = 0; i < upPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(up_propellers[i]);
							if (prop is null || !up) continue;

							if (prop !is null && seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_f32("powerFactor", prop.get_f32("initPowerFactor")*power);
							}
						}
						for (u16 i = 0; i < downPropLength; ++i)
						{
							CBlob@ prop = getBlobByNetworkID(down_propellers[i]);
							if (prop is null || !down) continue;

							if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
							{
								prop.set_f32("powerFactor", prop.get_f32("initPowerFactor")*power);
							}
						}
					}
					else if (left || right)
					{
						this.set_bool("kLR", true);

						if (!strafe)
						{
							for (u16 i = 0; i < leftPropLength; ++i)
							{
								CBlob@ prop = getBlobByNetworkID(left_propellers[i]);
								if (prop is null || !left) continue;

								if (seatColor == prop.getShape().getVars().customData &&  (teamInsensitive || occupierTeam == prop.getTeamNum()))
								{
									prop.set_f32("powerFactor", prop.get_f32("initPowerFactor")*power);
								}
							}
							for (u16 i = 0; i < rightPropLength; ++i)
							{
								CBlob@ prop = getBlobByNetworkID(right_propellers[i]);
								if (prop is null || !right) continue;

								if (seatColor == prop.getShape().getVars().customData && (teamInsensitive || occupierTeam == prop.getTeamNum()))
								{
									prop.set_f32("powerFactor", prop.get_f32("initPowerFactor")*power);
								}
							}
						}
					}
				}
			}
			//if (occupier.getPlayer() !is null && occupier.getPlayer().getUsername() == "NoahTheLegend")
			//	printf("sp "+space+" hold "+Human::isHoldingBlocks(occupier)+" held "+Human::wasHoldingBlocks(occupier));
			if (!space && !Human::isHoldingBlocks(occupier) && !Human::wasHoldingBlocks(occupier))
			{
				//machineguns on left click
				if (left_click)
				{
					Vec2f aim = occupier.getAimPos() - this.getPosition();//relative to seat
					const u16 machinegunsLength = machineguns.length;
					for (u16 i = 0; i < machinegunsLength; ++i)
					{
						CBlob@ weap = getBlobByNetworkID(machineguns[i]);
						if (weap is null) continue;

						Vec2f dirFacing = Vec2f(1, 0).RotateBy(weap.getAngleDegrees());
						if (Maths::Abs(dirFacing.AngleWith(aim)) < 40)
						{
							CBitStream bs;
							bs.write_netid(occupier.getNetworkID());
							weap.SendCommand(weap.getCommandID("fire"), bs);
						}
					}
				}
				//cannons on right click
				const u16 cannonsLength = cannons.length;
				if (right_click && cannonsLength > 0 && this.get_u32("lastCannonFire") + CANNON_FIRE_CYCLE < gameTime)
				{
					CBlob@[] fireCannons;
					Vec2f aim = occupier.getAimPos() - this.getPosition();//relative to seat
					CBlob@ fitCannon = getMap().getBlobAtPosition(occupier.getAimPos());

					for (u16 i = 0; i < cannonsLength; ++i)
					{
						CBlob@ weap = getBlobByNetworkID(cannons[i]);
						if (weap is null || !weap.get_bool("fire ready")) continue;

						Vec2f dirFacing = Vec2f(1, 0).RotateBy(weap.getAngleDegrees());
						if (fitCannon !is null)
						{
							//blob has to be on our ship and must be a cannon
							if (!fitCannon.hasTag("cannon") || fitCannon.getShape().getVars().customData != seatColor)
								@fitCannon = null;
							else
								fireCannons.push_back(fitCannon);
						}
						else if (Maths::Abs(dirFacing.AngleWith(aim)) < 40)
						if (Maths::Abs(dirFacing.AngleWith(aim)) < 40)
							fireCannons.push_back(weap);
					}

					if (fireCannons.length > 0)
					{
						const u8 index = this.get_u8("cannonFireIndex");
						CBlob@ weap = fireCannons[index % fireCannons.length];
						CBitStream bs;
						bs.write_netid(occupier.getNetworkID());
						weap.SendCommand(weap.getCommandID("fire"), bs);
						this.set_u32("lastCannonFire", gameTime);
						this.set_u8("cannonFireIndex", index + 1);
					}
				}
			}
		}
	}
	else if (isServer() && ship.copilot == seatOwner) //captain seats release rates
	{
		if ((ship.pos - ship.old_pos).Length() > 0.01f) //keep extra seats alive while the mothership moves
			this.set_u32("lastActive", gameTime);
		else //release seat faster for when captain abandons the ship
			this.set_u32("lastActive", Maths::Max(0, this.get_u32("lastActive") - 2));
	}
}

//stop props on sit down if possible
void onAttach(CBlob@ this, CBlob@ attached, AttachmentPoint@ attachedPoint)
{
	if (isServer())
	{
		this.set_bool("kUD", true);
		this.set_bool("kLR", true);
	}
}

//keep props alive onDetach
void onDetach(CBlob@ this, CBlob@ detached, AttachmentPoint@ attachedPoint)
{
	if (isServer())
	{
		this.set_bool("kUD", false);
		this.set_bool("kLR", false);
	}
}

void updateArrays(CBlob@ this, Ship@ ship)
{
	this.set_bool("updateBlock", false);

	u16[] left_propellers, strafe_left_propellers, strafe_right_propellers, right_propellers, up_propellers, down_propellers, machineguns, cannons;	
	const u16 blocksLength = ship.blocks.length;
	for (u16 i = 0; i < blocksLength; ++i)
	{
		ShipBlock@ ship_block = ship.blocks[i];
		if (ship_block is null) continue;

		CBlob@ block = getBlobByNetworkID(ship_block.blobID);
		if (block is null) continue;
		
		const u16 netID = block.getNetworkID();
		//machineguns
		if (block.hasTag("machinegun"))
			machineguns.push_back(netID);
		else if (block.hasTag("cannon"))
			cannons.push_back(netID);
		
		//propellers
		if (block.hasTag("engine"))
		{
			Vec2f _veltemp, velNorm;
			float angleVel;
			PropellerForces(block, ship, 1.0f, _veltemp, velNorm, angleVel);

			velNorm.RotateBy(-this.getAngleDegrees());
			
			const float angleLimit = 0.05f;
			const float forceLimit = 0.01f;
			const float forceLimit_side = 0.2f;

			if (angleVel < -angleLimit || (velNorm.y < -forceLimit_side && angleVel < angleLimit))
				right_propellers.push_back(netID);
			else if (angleVel > angleLimit || (velNorm.y > forceLimit_side && angleVel > -angleLimit))
				left_propellers.push_back(netID);
			
			if (Maths::Abs(velNorm.x) < forceLimit)
			{
				if (velNorm.y < -forceLimit_side)
					strafe_right_propellers.push_back(netID);
				else if (velNorm.y > forceLimit_side)
					strafe_left_propellers.push_back(netID);
			}
					
			if (velNorm.x > forceLimit)
				down_propellers.push_back(netID);
			else if (velNorm.x < -forceLimit)
				up_propellers.push_back(netID);
		}
	}
	
	cannons.sortAsc();
	
	this.set("left_propellers", left_propellers);
	this.set("strafe_left_propellers", strafe_left_propellers);
	this.set("strafe_right_propellers", strafe_right_propellers);
	this.set("right_propellers", right_propellers);
	this.set("up_propellers", up_propellers);
	this.set("down_propellers", down_propellers);
	this.set("machineguns", machineguns);
	this.set("cannons", cannons);
}

void server_setOwner(CBlob@ this, const string&in owner)
{
	//print("" + this.getNetworkID() + " seat setOwner: " + owner);
	this.set_string("playerOwner", owner);
	this.Sync("playerOwner", true);
	this.set_u32("lastOwnerUpdate", getGameTime());
}
